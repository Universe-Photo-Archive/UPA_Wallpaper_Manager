import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import '../models/theme_category.dart';
import '../models/theme_source.dart';
import '../models/wallpaper_image.dart';

/// Service that turns a local folder into a wallpaper theme.
///
/// Unlike Piwigo themes (loaded over HTTP), local themes are read directly
/// from disk. Each scanned image is exposed as a [WallpaperImage] whose
/// `localPath` is the on-disk path — the cache layer treats it as already
/// "downloaded" so rotation can apply it directly.
class LocalGalleryService {
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.gif',
    '.tif',
    '.tiff',
  };

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Resolves a [LocalSource] into the [ThemeCategory] visible in the UI.
  /// Counts how many supported image files are present so the dropdown
  /// shows the same "(N)" decoration as Piwigo themes.
  Future<ThemeCategory> resolveCategory(LocalSource source) async {
    final files = await _scanFiles(source.folderPath, source.recursive);
    return ThemeCategory(
      id: source.id,
      name: source.name,
      nameRaw: source.name,
      url: source.folderPath,
      imageCount: files.length,
      thumbnailUrl: files.isNotEmpty ? files.first.path : null,
      sourceBaseUrl: source.sourceBaseUrl,
      isUserAdded: true,
      originalUrl: source.folderPath,
    );
  }

  /// Reads images for a local theme. Each image is returned with
  /// `isDownloaded = true` and `localPath` set to its absolute path.
  Future<List<WallpaperImage>> getImages(LocalSource source) async {
    final files = await _scanFiles(source.folderPath, source.recursive);
    final images = <WallpaperImage>[];
    for (final file in files) {
      final path = file.path;
      images.add(WallpaperImage(
        id: _stableId(path),
        filename: p.basename(path),
        pageUrl: path,
        cachedFullSizeUrl: path,
        isDownloaded: true,
        localPath: path,
        derivatives: const {},
      ));
    }
    _log.i('Local gallery "${source.name}": ${images.length} image(s) '
        'from ${source.folderPath}');
    return images;
  }

  /// Returns true if the folder still exists on disk.
  bool exists(LocalSource source) {
    return Directory(source.folderPath).existsSync();
  }

  Future<List<File>> _scanFiles(String path, bool recursive) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      _log.w('Local gallery folder missing: $path');
      return [];
    }

    final files = <File>[];
    try {
      await for (final entity
          in dir.list(recursive: recursive, followLinks: false)) {
        if (entity is File && _isImage(entity.path)) {
          files.add(entity);
        }
      }
    } catch (e) {
      _log.e('Failed to scan local folder $path: $e');
    }

    files.sort((a, b) => p
        .basename(a.path)
        .toLowerCase()
        .compareTo(p.basename(b.path).toLowerCase()));
    return files;
  }

  bool _isImage(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return _imageExtensions.contains(ext);
  }

  /// Stable positive int id so the same file is treated as the same image
  /// across runs (`hashCode` is deterministic per session in Dart, but path
  /// is the canonical identity here).
  int _stableId(String path) {
    // Mask to 31 bits to stay safely positive on all platforms.
    return path.hashCode & 0x7fffffff;
  }
}
