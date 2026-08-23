import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:logger/logger.dart';
import '../models/wallpaper_image.dart';
import 'cache_service.dart';

typedef RotationCallback = void Function(int screenId, String imagePath);

class ScreenRotationConfig {
  final int screenId;

  /// Themes this screen draws from; empty means every known theme.
  List<String> themeNames;
  bool enabled;
  int delaySeconds;

  ScreenRotationConfig({
    required this.screenId,
    this.themeNames = const [],
    this.enabled = true,
    this.delaySeconds = 900,
  });
}

/// Manages wallpaper rotation with per-screen timers and anti-duplicate logic.
class RotationService {
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final CacheService _cache;

  bool randomMode;
  bool _running = false;
  bool _paused = false;
  RotationCallback? onRotation;

  final Map<int, ScreenRotationConfig> _screenConfigs = {};
  final Map<int, Timer?> _screenTimers = {};
  final Map<int, String> _currentWallpapers = {};
  final Map<int, String> _currentThemes = {};

  List<String> allThemeNames = [];

  /// Consulted before every scheduled rotation. Returning false skips the
  /// turn without stopping the timer — used for the quiet-hours window.
  /// Rotations the user asks for explicitly are never affected.
  bool Function()? shouldRotateNow;

  RotationService({
    required CacheService cache,
    this.randomMode = true,
  }) : _cache = cache;

  bool get isRunning => _running;
  bool get isPaused => _paused;
  bool get isActive => _running && !_paused;
  Map<int, String> get currentWallpapers => Map.unmodifiable(_currentWallpapers);
  Map<int, String> get currentThemes => Map.unmodifiable(_currentThemes);

  /// Returns the configured theme name for [screenId] (or null when the
  /// screen is unknown). Resolves "all" to whatever theme was last shown.
  String? themeNameForScreen(int screenId) {
    final config = _screenConfigs[screenId];
    if (config == null) return _currentThemes[screenId];
    if (config.themeNames.length == 1) return config.themeNames.first;
    return _currentThemes[screenId];
  }

  void setScreenConfig(ScreenRotationConfig config) {
    _screenConfigs[config.screenId] = config;
  }

  void removeScreen(int screenId) {
    _screenConfigs.remove(screenId);
    _screenTimers[screenId]?.cancel();
    _screenTimers.remove(screenId);
    _currentWallpapers.remove(screenId);
    _currentThemes.remove(screenId);
  }

  void start() {
    if (_running) return;
    _running = true;
    _paused = false;
    for (final config in _screenConfigs.values) {
      if (config.enabled) _scheduleScreen(config);
    }
    _log.i('Rotation started (per-screen delays, random: $randomMode)');
  }

  void stop() {
    _running = false;
    for (final timer in _screenTimers.values) {
      timer?.cancel();
    }
    _screenTimers.clear();
    _log.i('Rotation stopped');
  }

  void pause() {
    _paused = true;
    for (final timer in _screenTimers.values) {
      timer?.cancel();
    }
    _screenTimers.clear();
    _log.i('Rotation paused');
  }

  void resume() {
    if (!_running) return;
    _paused = false;
    for (final config in _screenConfigs.values) {
      if (config.enabled) _scheduleScreen(config);
    }
    _log.i('Rotation resumed');
  }

  /// Restart all timers with current configs (called after settings change).
  void restartTimers() {
    for (final timer in _screenTimers.values) {
      timer?.cancel();
    }
    _screenTimers.clear();
    for (final config in _screenConfigs.values) {
      if (config.enabled) _scheduleScreen(config);
    }
    _log.i('Timers restarted with updated configs');
  }

  bool togglePause() {
    if (_paused) {
      resume();
    } else {
      pause();
    }
    return _paused;
  }

  Future<void> rotateNow() async {
    _log.i('Forced rotation for all screens');
    await _performRotationAll();
    if (_running && !_paused) {
      for (final config in _screenConfigs.values) {
        if (config.enabled) _scheduleScreen(config);
      }
    }
  }

  /// Force rotation for a single screen (e.g. after theme change).
  Future<void> rotateScreen(int screenId) async {
    final config = _screenConfigs[screenId];
    if (config == null) return;
    _log.i('Forced rotation for screen $screenId');
    await _rotateScreen(config);
    if (_running && !_paused && config.enabled) {
      _scheduleScreen(config);
    }
  }

  void _scheduleScreen(ScreenRotationConfig config) {
    _screenTimers[config.screenId]?.cancel();
    _screenTimers[config.screenId] = Timer(
      Duration(seconds: config.delaySeconds),
      () async {
        if (!_running || _paused) return;
        if (shouldRotateNow?.call() == false) {
          _log.d('Rotation skipped for screen ${config.screenId} '
              '(outside the allowed hours)');
        } else {
          await _rotateScreen(config);
        }
        if (_running && !_paused && config.enabled) {
          _scheduleScreen(config);
        }
      },
    );
  }

  Future<void> _performRotationAll() async {
    if (onRotation == null) return;
    for (final config in _screenConfigs.values) {
      if (!config.enabled) continue;
      await _rotateScreen(config);
    }
  }

  Future<void> _rotateScreen(ScreenRotationConfig config) async {
    if (onRotation == null) return;

    try {
      final imagePath = await _getNextImageForScreen(config);
      if (imagePath != null) {
        final filename = imagePath.split('/').last.split('\\').last;
        _currentWallpapers[config.screenId] = filename;

        // Protect the file from cache cleanup while it is on screen, so the
        // preview and the OS wallpaper never point to a deleted file.
        _cache.pinWallpaper(config.screenId, imagePath);

        // Resolve theme from the path layout `<cacheDir>/<theme>/<file>`.
        final normalized = imagePath.replaceAll('\\', '/');
        final parts = normalized.split('/');
        if (parts.length >= 2) {
          _currentThemes[config.screenId] = parts[parts.length - 2];
        }

        // Notify AFTER tracking maps are updated so listeners see the
        // up-to-date theme/screen mapping.
        onRotation!(config.screenId, imagePath);
      } else {
        _log.w('No image available for screen ${config.screenId}');
      }
    } catch (e) {
      _log.e('Rotation error for screen ${config.screenId}: $e');
    }
  }

  /// Selects the next image from the FULL catalog (not just downloaded ones),
  /// downloads it on-demand if needed, and ensures every image in the theme
  /// is shown exactly once before the cycle resets.
  Future<String?> _getNextImageForScreen(ScreenRotationConfig config) async {
    final themes =
        config.themeNames.isEmpty ? allThemeNames : config.themeNames;

    // Build list of ALL images (downloaded or not) for the theme(s)
    final allImages = <_Candidate>[];
    for (final theme in themes) {
      for (final img in _cache.getThemeImages(theme)) {
        allImages.add(_Candidate(theme, img));
      }
    }

    if (allImages.isEmpty) return null;

    // What's currently on other screens (avoid duplicates)
    final otherFilenames = <String>{};
    final otherThemes = <String>{};
    _currentWallpapers.forEach((sid, fn) {
      if (sid != config.screenId) otherFilenames.add(fn);
    });
    _currentThemes.forEach((sid, tn) {
      if (sid != config.screenId) otherThemes.add(tn);
    });

    // 1) Undisplayed images (full cycle tracking)
    var eligible = allImages.where((c) {
      if (c.image.isDisplayed) return false;
      if (otherFilenames.contains(c.image.filename)) return false;
      if (themes.length > 1 && otherThemes.contains(c.theme)) {
        return false;
      }
      return true;
    }).toList();

    // 2) If all images have been displayed → reset cycle
    if (eligible.isEmpty) {
      final totalUndisplayed = allImages.where((c) => !c.image.isDisplayed).length;
      if (totalUndisplayed == 0) {
        _log.i('Full cycle complete for ${themes.join(", ")} '
            '(${allImages.length} images). Resetting.');
        for (final theme in themes) {
          _cache.resetCycle(theme);
        }
      }
      // Re-filter after reset
      eligible = allImages.where((c) {
        if (c.image.isDisplayed) return false;
        if (otherFilenames.contains(c.image.filename)) return false;
        return true;
      }).toList();
    }

    if (eligible.isEmpty) eligible = allImages.toList();

    // 3) Pick from eligible
    final _Candidate chosen;
    if (randomMode) {
      chosen = eligible[Random().nextInt(eligible.length)];
    } else {
      chosen = eligible.first;
    }

    // 4) Download if not already cached
    if (!chosen.image.isDownloaded || chosen.image.localPath == null) {
      _log.d('Downloading on-demand: ${chosen.image.filename} '
          '(theme: ${chosen.theme})');
      final path = await _cache.downloadImage(chosen.theme, chosen.image);
      if (path == null) {
        _log.w('Download failed for ${chosen.image.filename}, trying fallback');
        return _fallbackToDownloaded(config, allImages, otherFilenames, otherThemes);
      }
    }

    // Verify the file still exists on disk
    if (chosen.image.localPath == null ||
        !await File(chosen.image.localPath!).exists()) {
      _log.w('File missing for ${chosen.image.filename}, trying fallback');
      chosen.image.isDownloaded = false;
      chosen.image.localPath = null;
      return _fallbackToDownloaded(config, allImages, otherFilenames, otherThemes);
    }

    _cache.markDisplayed(chosen.theme, chosen.image.localPath!);

    // 5) Prefetch next batch in the background (fire-and-forget)
    _prefetchForThemes(themes);

    return chosen.image.localPath;
  }

  /// Fallback: pick among already-downloaded images when on-demand download fails.
  Future<String?> _fallbackToDownloaded(
    ScreenRotationConfig config,
    List<_Candidate> allImages,
    Set<String> otherFilenames,
    Set<String> otherThemes,
  ) async {
    var downloaded = allImages
        .where((c) => c.image.isDownloaded && c.image.localPath != null)
        .toList();

    var eligible = downloaded.where((c) {
      if (c.image.isDisplayed) return false;
      if (otherFilenames.contains(c.image.filename)) return false;
      return true;
    }).toList();

    if (eligible.isEmpty) eligible = downloaded;
    if (eligible.isEmpty) return null;

    final chosen = randomMode
        ? eligible[Random().nextInt(eligible.length)]
        : eligible.first;

    _cache.markDisplayed(chosen.theme, chosen.image.localPath!);
    return chosen.image.localPath;
  }

  /// Prefetch a few undisplayed images to avoid download wait on next rotation.
  void _prefetchForThemes(List<String> themes) {
    for (final theme in themes) {
      final undisplayed = _cache.getUndisplayedImages(theme);
      final needDownload = undisplayed
          .where((img) => !img.isDownloaded)
          .take(3);
      if (needDownload.isNotEmpty) {
        _cache.downloadBatch(theme, count: 3);
      }
    }
  }
}

class _Candidate {
  final String theme;
  final WallpaperImage image;
  _Candidate(this.theme, this.image);
}
