import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../platform/media_access_channel.dart';
import 'cache_service.dart';

/// Small copies of banned photos, kept outside the wallpaper cache.
///
/// The exclusion list used to point at the full cached file. Cache cleanup
/// deletes those files, so the tiles went blank even though the ban itself
/// (theme + file name) was still in force. These thumbs live in their own
/// folder and are never swept with the wallpaper pool.
class ExclusionThumbsService {
  static const int maxSize = 400;

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'UPA-Wallpaper-Manager/2.0'},
    ),
  );

  late Directory _dir;

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _dir = Directory('${appDir.path}/exclusion_thumbs');
    await _dir.create(recursive: true);
    _log.i('Exclusion thumbs at ${_dir.path}');
  }

  /// Path of the persisted thumb when it is already on disk.
  String? existingPath(ExcludedImage image) {
    final file = File(_pathFor(image));
    if (file.existsSync() && file.lengthSync() > 0) return file.path;
    return null;
  }

  /// Returns a displayable path, generating or downloading the thumb if needed.
  Future<String?> resolve(ExcludedImage image, CacheService cache) async {
    final existing = existingPath(image);
    if (existing != null) return existing;

    final local = _usableReference(image.localPath);
    if (local != null) {
      final written = await persistFromReference(image, local);
      if (written != null) return written;
    }

    final cached = cache.getLocalPath(image.theme, image.filename);
    if (cached != null) {
      final written = await persistFromReference(image, cached);
      if (written != null) return written;
    }

    final url = image.thumbnailUrl ??
        cache.thumbnailUrlFor(image.theme, image.filename);
    if (url != null && url.isNotEmpty) {
      return persistFromUrl(image, url);
    }
    return null;
  }

  /// Rebuilds missing thumbs for exclusions that still have a file or a URL.
  Future<void> backfill(
    List<ExcludedImage> images,
    CacheService cache,
  ) async {
    for (final image in images) {
      try {
        await resolve(image, cache);
      } catch (e) {
        _log.w('Could not rebuild exclusion thumb for ${image.key}: $e');
      }
    }
  }

  Future<String?> persistFromReference(
    ExcludedImage image,
    String reference,
  ) async {
    final dest = File(_pathFor(image));
    try {
      if (MediaAccessChannel.isDocumentUri(reference)) {
        final generated = await MediaAccessChannel.thumbnail(
          reference,
          maxSize: maxSize,
        );
        if (generated == null) return null;
        await File(generated).copy(dest.path);
        return dest.existsSync() && dest.lengthSync() > 0 ? dest.path : null;
      }

      final source = File(reference);
      if (!source.existsSync() || source.lengthSync() <= 0) return null;
      if (await _writeResized(source, dest)) return dest.path;
    } catch (e) {
      _log.w('Could not persist exclusion thumb for ${image.key}: $e');
    }
    return null;
  }

  Future<String?> persistFromUrl(ExcludedImage image, String url) async {
    final dest = File(_pathFor(image));
    final part = File('${dest.path}.part');
    try {
      if (part.existsSync()) part.deleteSync();
      await _dio.download(url, part.path);
      if (!part.existsSync() || part.lengthSync() <= 0) {
        if (part.existsSync()) part.deleteSync();
        return null;
      }
      if (await _writeResized(part, dest)) {
        if (part.existsSync()) part.deleteSync();
        return dest.path;
      }
      await part.rename(dest.path);
      return dest.existsSync() && dest.lengthSync() > 0 ? dest.path : null;
    } catch (e) {
      _log.w('Could not download exclusion thumb for ${image.key}: $e');
      if (part.existsSync()) part.deleteSync();
    }
    return null;
  }

  Future<void> remove(ExcludedImage image) async {
    try {
      final file = File(_pathFor(image));
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log.w('Could not delete exclusion thumb for ${image.key}: $e');
    }
  }

  Future<void> removeAll() async {
    try {
      if (await _dir.exists()) {
        await _dir.delete(recursive: true);
        await _dir.create(recursive: true);
      }
    } catch (e) {
      _log.w('Could not clear exclusion thumbs: $e');
    }
  }

  String _pathFor(ExcludedImage image) {
    final name = base64Url.encode(utf8.encode(image.key)).replaceAll('=', '');
    return '${_dir.path}/$name.thumb';
  }

  String? _usableReference(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    if (MediaAccessChannel.isDocumentUri(reference)) return reference;
    final file = File(reference);
    if (file.existsSync() && file.lengthSync() > 0) return reference;
    return null;
  }

  Future<bool> _writeResized(File source, File dest) async {
    try {
      final bytes = await source.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxSize,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      codec.dispose();
      if (data == null) return false;
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return dest.existsSync() && dest.lengthSync() > 0;
    } catch (e) {
      _log.w('Could not resize exclusion thumb: $e');
      return false;
    }
  }
}
