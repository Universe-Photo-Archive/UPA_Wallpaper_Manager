import 'dart:io';
import 'package:flutter/services.dart';
import '../models/screen_info.dart';

/// Platform channel for setting wallpapers natively on each OS.
class WallpaperChannel {
  static const _channel = MethodChannel('eu.universe_photo_archive/wallpaper');

  /// Sets the wallpaper for a specific screen.
  /// [imagePath] must be an absolute local file path.
  /// [screenId] targets a specific monitor (desktop) or is ignored (mobile).
  /// [fitMode] can be 'fill', 'fit', 'stretch', 'center', 'tile', 'span'.
  static Future<bool> setWallpaper({
    required String imagePath,
    int? screenId,
    String fitMode = 'fill',
  }) async {
    if (!_exists(imagePath)) return false;

    try {
      final result = await _channel.invokeMethod<bool>('setWallpaper', {
        'imagePath': imagePath,
        'screenId': screenId,
        'fitMode': fitMode,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Platform not implemented yet — return false gracefully
      return false;
    }
  }

  /// Returns the absolute path of the wallpaper currently displayed by the
  /// OS on [screenId] (or the global wallpaper when [screenId] is null).
  /// Returns null if the platform does not support querying the wallpaper,
  /// the call fails, or the resulting path does not exist on disk.
  static Future<String?> getWallpaper({int? screenId}) async {
    try {
      final result = await _channel.invokeMethod<String>('getWallpaper', {
        'screenId': screenId,
      });
      if (result == null || result.isEmpty) return null;
      if (!File(result).existsSync()) return null;
      return result;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Gets the list of connected screens/monitors.
  static Future<List<ScreenInfo>> getScreens() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getScreens');
      if (result == null) return _defaultScreen();

      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return ScreenInfo.fromJson(map);
      }).toList();
    } on PlatformException {
      return _defaultScreen();
    } on MissingPluginException {
      return _defaultScreen();
    }
  }

  static List<ScreenInfo> _defaultScreen() {
    return [
      const ScreenInfo(
        id: 0,
        name: 'Screen 1',
        width: 1920,
        height: 1080,
        isPrimary: true,
      ),
    ];
  }

  /// Applies [imagePath] to the home wallpaper and the lock screen at once.
  static Future<bool> setBothWallpapers(String imagePath) async {
    if (!_exists(imagePath)) return false;
    try {
      final result = await _channel.invokeMethod<bool>('setBothWallpapers', {
        'imagePath': imagePath,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// A reference is either a file or one of the user's photos, which only
  /// the platform can open.
  static bool _exists(String reference) =>
      reference.startsWith('content://') || File(reference).existsSync();

  /// Shortest period WorkManager accepts for a periodic job. Only relevant to
  /// the fallback that covers the foreground service being killed.
  static const int minBackgroundIntervalMinutes = 15;

  /// Starts (or refreshes) the foreground service driving the slideshow.
  static Future<void> startForegroundRotation() =>
      _invokeVoid('startForegroundRotation');

  /// Stops the slideshow service and removes its notification.
  static Future<void> stopForegroundRotation() =>
      _invokeVoid('stopForegroundRotation');

  /// Schedules the fallback job used when the service is not running.
  static Future<void> schedulePeriodicRotation({
    required int intervalMinutes,
  }) =>
      _invokeVoid('schedulePeriodicRotation', {
        'intervalMinutes': intervalMinutes < minBackgroundIntervalMinutes
            ? minBackgroundIntervalMinutes
            : intervalMinutes,
      });

  /// Cancels the fallback job.
  static Future<void> cancelPeriodicRotation() =>
      _invokeVoid('cancelPeriodicRotation');

  /// Listens to what the slideshow service does while the app is running, so
  /// the previews and the switches follow the device.
  static void listenToNativeRotation({
    required void Function(int screenId, String path) onWallpaperChanged,
    required void Function() onSlideshowStopped,
  }) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'wallpaperChanged':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final path = args['path'] as String?;
          final screenId = args['screenId'] as int? ?? 0;
          if (path != null && path.isNotEmpty) {
            onWallpaperChanged(screenId, path);
          }
        case 'slideshowStopped':
          onSlideshowStopped();
      }
      return null;
    });
  }

  static Future<void> _invokeVoid(String method,
      [Map<String, dynamic>? args]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod(method, args);
    } on PlatformException {
      // Rotation still works while the app is open.
    } on MissingPluginException {
      // Older native build — same graceful degradation.
    }
  }
}
