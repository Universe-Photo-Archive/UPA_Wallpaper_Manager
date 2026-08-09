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
    if (!File(imagePath).existsSync()) return false;

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
}
