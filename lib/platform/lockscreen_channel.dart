import 'dart:io';
import 'package:flutter/services.dart';

/// Platform channel for setting the lockscreen image.
class LockscreenChannel {
  static const _channel = MethodChannel('eu.universe_photo_archive/lockscreen');

  /// Sets the lock screen image.
  /// Returns true if successful. May require admin privileges on Windows.
  static Future<bool> setLockscreen(String imagePath) async {
    if (!File(imagePath).existsSync()) return false;

    try {
      final result = await _channel.invokeMethod<bool>('setLockscreen', {
        'imagePath': imagePath,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Removes the custom lockscreen configuration, returning control to the OS.
  static Future<bool> removeLockscreen() async {
    try {
      final result = await _channel.invokeMethod<bool>('removeLockscreen');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Checks if the lockscreen feature is available on this platform.
  static Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Checks if the app has admin/elevated privileges (Windows).
  static Future<bool> isAdmin() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAdmin');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Checks if the running Windows edition supports the PersonalizationCSP
  /// lock screen mechanism (Pro / Enterprise / Education / Server).
  /// Returns false on Home editions where the registry is silently ignored.
  static Future<bool> isWindowsEditionSupported() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isWindowsEditionSupported');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns true only if both [isAdmin] and [isWindowsEditionSupported] are
  /// true. The lock screen feature should be hidden / disabled in the UI when
  /// this is false.
  static Future<bool> isLockscreenSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLockscreenSupported');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
