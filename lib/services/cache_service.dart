import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import '../models/wallpaper_image.dart';

/// Smart cache manager — mirrors the Python SmartCacheManager logic.
/// Handles downloading, indexing, cycle tracking, and cleanup.
class CacheService {
  static const int defaultMaxImages = 25;
  static const int defaultPrefetchCount = 10;

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'User-Agent': 'UPA-Wallpaper-Manager/2.0'},
  ));

  late Directory _cacheDir;
  int maxCachedImages;
  int prefetchCount;

  /// Index: themeName -> list of WallpaperImage (with cache metadata)
  final Map<String, List<WallpaperImage>> _index = {};
  final Map<String, int> _currentCycle = {};

  /// Wallpaper currently applied on each screen. These files are protected
  /// from [cleanupIfNeeded] so the home-screen preview (and the OS wallpaper
  /// reference) never points to a deleted file.
  final Map<int, String> _pinnedWallpapers = {};

  CacheService({
    this.maxCachedImages = defaultMaxImages,
    this.prefetchCount = defaultPrefetchCount,
  });

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${appDir.path}/wallpapers');
    await _cacheDir.create(recursive: true);
    await _loadIndex();
    _log.i('CacheService initialized at ${_cacheDir.path}');
  }

  String get cacheDirPath => _cacheDir.path;

  // --- Index persistence ---

  File get _indexFile => File('${_cacheDir.path}/smart_index.json');

  Future<void> _loadIndex() async {
    if (!await _indexFile.exists()) return;
    try {
      final data =
          json.decode(await _indexFile.readAsString()) as Map<String, dynamic>;
      final themes = data['themes'] as Map<String, dynamic>? ?? {};
      themes.forEach((themeName, themeData) {
        final td = themeData as Map<String, dynamic>;
        final images = (td['images'] as List<dynamic>?)
                ?.map((i) => WallpaperImage.fromJson(i as Map<String, dynamic>))
                .toList() ??
            [];
        _index[themeName] = images;
        _currentCycle[themeName] = td['currentCycle'] as int? ?? 0;
      });
      _log.i('Cache index loaded: ${_index.length} themes');
    } catch (e) {
      _log.e('Failed to load cache index: $e');
    }
  }

  Future<void> _saveIndex() async {
    try {
      final themes = <String, dynamic>{};
      _index.forEach((themeName, images) {
        themes[themeName] = {
          'images': images.map((i) => i.toJson()).toList(),
          'currentCycle': _currentCycle[themeName] ?? 0,
        };
      });
      await _indexFile.writeAsString(json.encode({'themes': themes}));
    } catch (e) {
      _log.e('Failed to save cache index: $e');
    }
  }

  // --- Theme images management ---

  /// Updates the known image list for a theme (from API data).
  /// Refreshes download URLs for existing images and adds new ones.
  void updateThemeImages(String themeName, List<WallpaperImage> apiImages) {
    final existing = _index[themeName] ?? [];
    final existingById = {for (final img in existing) img.id: img};

    for (final apiImg in apiImages) {
      final cached = existingById[apiImg.id];
      if (cached != null) {
        cached.mergeApiData(apiImg);
      } else {
        existing.add(apiImg);
      }
    }
    _index[themeName] = existing;
    _currentCycle.putIfAbsent(themeName, () => 0);
    _saveIndex();
  }

  List<WallpaperImage> getThemeImages(String themeName) =>
      _index[themeName] ?? [];

  /// Marks [path] as the wallpaper currently shown on [screenId], protecting
  /// the file from cache cleanup for as long as it stays current.
  void pinWallpaper(int screenId, String path) {
    _pinnedWallpapers[screenId] = _normalizePath(path);
  }

  // --- Download ---

  /// Downloads a single image and returns the local path.
  Future<String?> downloadImage(
      String themeName, WallpaperImage image) async {
    // Local-gallery images are already on disk — no download needed.
    if (image.localPath != null && File(image.localPath!).existsSync()) {
      image.isDownloaded = true;
      return image.localPath;
    }

    final themeDir = Directory('${_cacheDir.path}/$themeName');
    await themeDir.create(recursive: true);

    final localPath = '${themeDir.path}/${image.filename}';

    // Already downloaded?
    if (File(localPath).existsSync()) {
      image.isDownloaded = true;
      image.localPath = localPath;
      return localPath;
    }

    // Download to a temporary name and rename once complete. Writing straight
    // to [localPath] left a truncated file behind whenever the process was
    // killed mid-download (routine on Android when the screen locks); that
    // half-written file then looked cached and was applied as wallpaper,
    // which the system renders as a blank / default background.
    final partPath = '$localPath.part';
    try {
      final url = image.fullSizeUrl;
      _log.d('Downloading ${image.filename} from $url');

      final part = File(partPath);
      if (part.existsSync()) part.deleteSync();

      await _dio.download(url, partPath);

      if (part.existsSync() && part.lengthSync() > 0) {
        await part.rename(localPath);
        image.isDownloaded = true;
        image.localPath = localPath;
        await _saveIndex();
        _log.i('Downloaded: ${image.filename}');
        return localPath;
      }
      if (part.existsSync()) part.deleteSync();
    } catch (e) {
      _log.e('Download failed for ${image.filename}: $e');
      for (final path in [partPath, localPath]) {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      }
    }
    return null;
  }

  /// Downloads a batch of images for a theme that are not yet cached.
  Future<int> downloadBatch(String themeName, {int? count}) async {
    count ??= prefetchCount;
    final images = _index[themeName] ?? [];
    final toDownload =
        images.where((i) => !i.isDownloaded && !i.isDisplayed).take(count);

    int downloaded = 0;
    for (final img in toDownload) {
      final result = await downloadImage(themeName, img);
      if (result != null) downloaded++;
    }

    if (downloaded > 0) await cleanupIfNeeded();
    return downloaded;
  }

  // --- Cache queries ---

  /// Returns local paths of cached (downloaded) images for a theme.
  ///
  /// Zero-length files are rejected: they can only be leftovers from an
  /// interrupted download and would be applied as a blank wallpaper.
  List<String> getCachedPaths(String themeName, {bool onlyUndisplayed = false}) {
    final images = _index[themeName] ?? [];
    return images
        .where((i) =>
            i.isDownloaded &&
            i.localPath != null &&
            _isUsableFile(i.localPath!) &&
            (!onlyUndisplayed || !i.isDisplayed))
        .map((i) => i.localPath!)
        .toList();
  }

  bool _isUsableFile(String filePath) {
    final file = File(filePath);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Gets the local path for a specific image, or null if not cached.
  String? getLocalPath(String themeName, String filename) {
    final images = _index[themeName] ?? [];
    try {
      final img = images.firstWhere((i) => i.filename == filename);
      if (img.isDownloaded && img.localPath != null) {
        return File(img.localPath!).existsSync() ? img.localPath : null;
      }
    } catch (_) {}
    return null;
  }

  // --- Display tracking ---

  void markDisplayed(String themeName, String localPath) {
    final images = _index[themeName] ?? [];
    for (final img in images) {
      if (img.localPath == localPath) {
        img.isDisplayed = true;
        img.displayCount++;
        img.lastDisplayed = DateTime.now();
        break;
      }
    }
    _saveIndex();
  }

  bool isImageDisplayed(String themeName, String filename) {
    final images = _index[themeName] ?? [];
    try {
      return images.firstWhere((i) => i.filename == filename).isDisplayed;
    } catch (_) {
      return false;
    }
  }

  /// Returns the number of images not yet displayed in the current cycle.
  int getUndisplayedCount(String themeName) {
    final images = _index[themeName] ?? [];
    return images.where((i) => !i.isDisplayed).length;
  }

  /// Returns all undisplayed images for a theme (including non-downloaded).
  List<WallpaperImage> getUndisplayedImages(String themeName) {
    final images = _index[themeName] ?? [];
    return images.where((i) => !i.isDisplayed).toList();
  }

  /// Resets display cycle for a theme (all images become undisplayed).
  void resetCycle(String themeName) {
    final images = _index[themeName] ?? [];
    for (final img in images) {
      img.isDisplayed = false;
    }
    _currentCycle[themeName] = (_currentCycle[themeName] ?? 0) + 1;
    _saveIndex();
    _log.i('Cycle reset for "$themeName" — cycle #${_currentCycle[themeName]} '
        '(${images.length} images ready for new cycle)');
  }

  // --- Cleanup ---

  /// Frees disk space by removing already-displayed images first,
  /// preserving undisplayed images so the full cycle can complete.
  ///
  /// Only files that live inside the cache directory are considered for
  /// deletion. User-provided local-gallery files outside [_cacheDir] are
  /// never touched — they are referenced in place.
  Future<void> cleanupIfNeeded() async {
    int totalDownloaded = 0;
    final displayed = <_CacheItem>[];
    final undisplayed = <_CacheItem>[];
    final pinned = _pinnedWallpapers.values.toSet();

    _index.forEach((themeName, images) {
      for (final img in images) {
        if (img.isDownloaded && img.localPath != null) {
          if (!_isInCacheDir(img.localPath!)) continue;
          // Never delete a wallpaper that is currently applied on a screen.
          if (pinned.contains(_normalizePath(img.localPath!))) continue;
          totalDownloaded++;
          if (img.isDisplayed) {
            displayed.add(_CacheItem(themeName, img));
          } else {
            undisplayed.add(_CacheItem(themeName, img));
          }
        }
      }
    });

    if (totalDownloaded <= maxCachedImages) return;

    // Delete displayed images first (oldest-displayed first)
    displayed.sort((a, b) =>
        (a.image.lastDisplayed ?? DateTime(2000))
            .compareTo(b.image.lastDisplayed ?? DateTime(2000)));

    int toDelete = totalDownloaded - maxCachedImages;
    int deleted = 0;

    for (final item in displayed) {
      if (toDelete <= 0) break;
      try {
        final f = File(item.image.localPath!);
        if (f.existsSync()) f.deleteSync();
        item.image.isDownloaded = false;
        item.image.localPath = null;
        deleted++;
        toDelete--;
      } catch (e) {
        _log.e('Cleanup failed for ${item.image.filename}: $e');
      }
    }

    if (deleted > 0) {
      _log.i('Cleaned up $deleted displayed images from cache '
          '($totalDownloaded → ${totalDownloaded - deleted})');
      await _saveIndex();
    }
  }

  // --- Stats ---

  /// Canonical form used to compare file paths regardless of separator style.
  String _normalizePath(String filePath) {
    try {
      return File(filePath).absolute.path.replaceAll('\\', '/');
    } catch (_) {
      return filePath.replaceAll('\\', '/');
    }
  }

  /// Returns true if [filePath] sits inside the managed cache directory,
  /// false for arbitrary user files (e.g. local-gallery sources).
  bool _isInCacheDir(String filePath) {
    try {
      final base = _cacheDir.absolute.path.replaceAll('\\', '/');
      return _normalizePath(filePath).startsWith(base);
    } catch (_) {
      return false;
    }
  }

  Future<int> getCacheSizeBytes() async {
    int total = 0;
    if (!_cacheDir.existsSync()) return 0;
    await for (final entity in _cacheDir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clearCache({String? themeName}) async {
    if (themeName != null) {
      final dir = Directory('${_cacheDir.path}/$themeName');
      if (dir.existsSync()) await dir.delete(recursive: true);
      _index.remove(themeName);
    } else {
      if (_cacheDir.existsSync()) {
        await _cacheDir.delete(recursive: true);
        await _cacheDir.create(recursive: true);
      }
      _index.clear();
      _currentCycle.clear();
    }
    await _saveIndex();
  }

  Map<String, dynamic> getStats(String themeName) {
    final images = _index[themeName] ?? [];
    return {
      'total': images.length,
      'downloaded': images.where((i) => i.isDownloaded).length,
      'displayed': images.where((i) => i.isDisplayed).length,
      'remaining': images.where((i) => !i.isDisplayed).length,
      'cycle': _currentCycle[themeName] ?? 0,
    };
  }
}

class _CacheItem {
  final String themeName;
  final WallpaperImage image;
  _CacheItem(this.themeName, this.image);
}
