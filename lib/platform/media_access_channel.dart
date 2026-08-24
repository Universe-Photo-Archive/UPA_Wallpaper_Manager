import 'dart:io';
import 'package:flutter/services.dart';

/// One photo of the user, referenced where it lives.
class DeviceImage {
  final String uri;
  final String name;

  const DeviceImage({required this.uri, required this.name});
}

/// Access to the user's own photo folders, without any storage permission.
///
/// On Android the user grants lasting access to a folder through the system
/// picker; that grant covers everything inside and survives reboots, so images
/// are read in place instead of being copied. Desktop needs none of this and
/// works with plain file paths, which is why most methods here are Android
/// only and the callers fall back to `dart:io`.
class MediaAccessChannel {
  static const _channel = MethodChannel('eu.universe_photo_archive/wallpaper');

  /// True for a reference that only the platform can read (Android SAF).
  static bool isDocumentUri(String reference) =>
      reference.startsWith('content://');

  /// Asks the user for a folder and keeps the access. Null if cancelled.
  static Future<String?> pickFolder() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('pickFolder');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Images contained in a granted folder, sub-folders included.
  static Future<List<DeviceImage>> listFolderImages(String uri) async {
    if (!Platform.isAndroid) return const [];
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('listFolderImages', {
        'uri': uri,
      });
      if (result == null) return const [];
      return result
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map((map) => DeviceImage(
                uri: map['uri'] as String? ?? '',
                name: map['name'] as String? ?? '',
              ))
          .where((image) => image.uri.isNotEmpty)
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Path of a small cached JPEG standing in for [uri], which Flutter cannot
  /// display directly. Null when the image cannot be read.
  static Future<String?> thumbnail(String uri, {int maxSize = 400}) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('folderThumbnail', {
        'uri': uri,
        'maxSize': maxSize,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// False once the user revoked the grant or removed the folder.
  static Future<bool> hasAccess(String uri) async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('hasFolderAccess', {
        'uri': uri,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Gives a folder grant back to the system when a theme is deleted.
  static Future<void> releaseFolder(String uri) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseFolder', {'uri': uri});
    } on PlatformException {
      // Nothing to do: the grant simply stays until the app is uninstalled.
    } on MissingPluginException {
      // Same.
    }
  }
}
