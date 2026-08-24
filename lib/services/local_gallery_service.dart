import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import '../models/theme_category.dart';
import '../models/theme_source.dart';
import '../models/wallpaper_image.dart';
import '../platform/media_access_channel.dart';

/// Turns the user's own photos into a theme, without ever copying them.
///
/// Desktop works with absolute paths. Android works with document URIs backed
/// by a lasting folder grant, which is why nothing has to be duplicated: both
/// the app and the background slideshow read the originals in place.
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
    '.heic',
    '.heif',
  };

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Describes [source] for the theme lists, image count included.
  Future<ThemeCategory> resolveCategory(LocalSource source) async {
    final images = await getImages(source);
    return ThemeCategory(
      id: source.numericId,
      name: source.name,
      nameRaw: source.name,
      url: source.roots.isEmpty ? '' : source.roots.first,
      imageCount: images.length,
      thumbnailUrl: images.isNotEmpty ? images.first.localPath : null,
      sourceBaseUrl: source.sourceBaseUrl,
      isUserAdded: true,
      originalUrl: source.roots.isEmpty ? null : source.roots.first,
    );
  }

  /// Images belonging to [source].
  ///
  /// A folder theme is re-read every time, so photos added to the folder show
  /// up and deleted ones disappear. A custom theme keeps only what the user
  /// ticked, minus anything that has since gone missing.
  Future<List<WallpaperImage>> getImages(LocalSource source) async {
    final references = source.isFolder
        ? await _enumerate(source.roots)
        : await _keepExisting(source.items);

    final images = [
      for (final reference in references)
        WallpaperImage(
          id: _stableId(reference),
          filename: _displayName(reference),
          pageUrl: reference,
          cachedFullSizeUrl: reference,
          isDownloaded: true,
          localPath: reference,
          derivatives: const {},
        )
    ];

    _log.i('Local theme "${source.name}": ${images.length} image(s)');
    return images;
  }

  /// Every image inside the granted folders.
  Future<List<String>> _enumerate(List<String> roots) async {
    final references = <String>[];
    for (final root in roots) {
      if (MediaAccessChannel.isDocumentUri(root)) {
        references.addAll(
          (await MediaAccessChannel.listFolderImages(root))
              .map((image) => image.uri),
        );
      } else {
        references.addAll(await _scanFolder(root));
      }
    }
    return references;
  }

  /// Drops references the user has since deleted or made unreachable.
  Future<List<String>> _keepExisting(List<String> references) async {
    final kept = <String>[];
    for (final reference in references) {
      if (MediaAccessChannel.isDocumentUri(reference)) {
        kept.add(reference);
      } else if (await File(reference).exists()) {
        kept.add(reference);
      }
    }
    return kept;
  }

  Future<List<String>> _scanFolder(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      _log.w('Local folder missing: $path');
      return [];
    }

    final files = <File>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isImage(entity.path)) files.add(entity);
      }
    } catch (e) {
      _log.e('Failed to scan local folder $path: $e');
    }

    files.sort((a, b) =>
        p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
    return files.map((f) => f.path).toList();
  }

  bool _isImage(String filePath) =>
      _imageExtensions.contains(p.extension(filePath).toLowerCase());

  String _displayName(String reference) {
    if (MediaAccessChannel.isDocumentUri(reference)) {
      final decoded = Uri.decodeComponent(reference);
      final segment = decoded.split('/').last;
      return segment.contains(':') ? segment.split(':').last : segment;
    }
    return p.basename(reference);
  }

  /// Stable positive id so the same photo is the same image across runs.
  int _stableId(String reference) => reference.hashCode & 0x7fffffff;
}
