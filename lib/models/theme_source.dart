/// A configured Piwigo source from which themes can be loaded.
///
/// Used both for the bundled / default config (themes_default.json)
/// and for user-added themes (themes_user.json). For default sources,
/// [recursive] is typically true — meaning all sub-categories of
/// [rootCategoryId] become themes. For user-added sources, [recursive]
/// is typically false — meaning a single category is the theme.
class PiwigoSource {
  /// Base URL of the Piwigo gallery (must end with a trailing slash).
  /// Example: https://universe-photo-archive.eu/gallery/
  final String baseUrl;

  /// Category ID. For default sources this is the root; for user-added
  /// it is the leaf category the user pasted.
  final int rootCategoryId;

  /// If true, all sub-categories are imported as themes.
  /// If false, only [rootCategoryId] itself is imported.
  final bool recursive;

  /// Original URL the user pasted (only meaningful for user-added sources).
  final String? originalUrl;

  /// Cached display name to show offline (only for user-added sources).
  final String? cachedName;

  /// Cached image count (only for user-added sources).
  final int? cachedImageCount;

  /// Cached thumbnail URL (only for user-added sources).
  final String? cachedThumbnailUrl;

  const PiwigoSource({
    required this.baseUrl,
    required this.rootCategoryId,
    this.recursive = false,
    this.originalUrl,
    this.cachedName,
    this.cachedImageCount,
    this.cachedThumbnailUrl,
  });

  factory PiwigoSource.fromJson(Map<String, dynamic> json) {
    return PiwigoSource(
      baseUrl: _normalizeBaseUrl(json['baseUrl'] as String? ?? ''),
      rootCategoryId: (json['rootCategoryId'] as int?) ??
          (json['categoryId'] as int?) ??
          0,
      recursive: json['recursive'] as bool? ?? false,
      originalUrl: json['originalUrl'] as String?,
      cachedName: json['cachedName'] as String?,
      cachedImageCount: json['cachedImageCount'] as int?,
      cachedThumbnailUrl: json['cachedThumbnailUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'rootCategoryId': rootCategoryId,
        'recursive': recursive,
        if (originalUrl != null) 'originalUrl': originalUrl,
        if (cachedName != null) 'cachedName': cachedName,
        if (cachedImageCount != null) 'cachedImageCount': cachedImageCount,
        if (cachedThumbnailUrl != null) 'cachedThumbnailUrl': cachedThumbnailUrl,
      };

  String get uniqueKey => '$baseUrl#$rootCategoryId';

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.endsWith('/')) u += '/';
    return u;
  }
}

/// A local folder used as a theme source (provider = "local gallery").
///
/// The folder is scanned recursively (one level by default) for images;
/// each image becomes a wallpaper of the synthetic theme. The folder path
/// itself is the stable identity — two different folders cannot collide.
class LocalSource {
  /// Absolute path to the folder containing images.
  final String folderPath;

  /// Display name shown in the gallery dropdown.
  final String name;

  /// Stable synthetic id, derived from [folderPath] hashCode. Stored so it
  /// survives JSON round-trips even though the platform may produce a
  /// different `String.hashCode` across processes — we persist it once.
  final int id;

  /// If true, sub-folders are also scanned for images.
  final bool recursive;

  const LocalSource({
    required this.folderPath,
    required this.name,
    required this.id,
    this.recursive = true,
  });

  /// Marker prefix used in [ThemeCategory.sourceBaseUrl] so the rest of the
  /// app can detect "this theme is local, do not call Piwigo".
  static const String urlScheme = 'local://';

  String get sourceBaseUrl => '$urlScheme$folderPath';

  factory LocalSource.fromJson(Map<String, dynamic> json) {
    final path = json['folderPath'] as String? ?? '';
    return LocalSource(
      folderPath: path,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : _deriveNameFromPath(path),
      id: (json['id'] as int?) ?? path.hashCode & 0x7fffffff,
      recursive: json['recursive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'folderPath': folderPath,
        'name': name,
        'id': id,
        'recursive': recursive,
      };

  String get uniqueKey => '$urlScheme$folderPath';

  static String _deriveNameFromPath(String path) {
    final clean = path.replaceAll('\\', '/').trimRight();
    final parts =
        clean.split('/').where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'Galerie locale';
    return parts.last;
  }
}

/// Result of parsing a raw Piwigo URL pasted by the user.
class ParsedPiwigoUrl {
  final String baseUrl;
  final int categoryId;
  final String? slug;

  const ParsedPiwigoUrl({
    required this.baseUrl,
    required this.categoryId,
    this.slug,
  });

  /// Parses URLs of the forms:
  ///   https://example.com/gallery/index.php?/category/45-cosmos
  ///   https://example.com/gallery/index.php?/category/45
  ///   https://example.com/index.php?/category/45-cosmos
  ///   https://example.com/gallery/category/45-cosmos
  /// Returns null if the URL is not a recognizable Piwigo album URL.
  static ParsedPiwigoUrl? parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;

    final categoryMatch =
        RegExp(r'/category/(\d+)(?:-([^/?&#]+))?').firstMatch(raw);
    if (categoryMatch == null) return null;

    final categoryId = int.tryParse(categoryMatch.group(1)!);
    if (categoryId == null) return null;
    final slug = categoryMatch.group(2);

    String base;
    final indexPhpIdx = raw.indexOf('index.php');
    if (indexPhpIdx > 0) {
      base = raw.substring(0, indexPhpIdx);
    } else {
      final catIdx = raw.indexOf('/category/');
      if (catIdx > 0) {
        base = raw.substring(0, catIdx + 1);
      } else {
        base = '${uri.scheme}://${uri.host}/';
      }
    }
    if (!base.endsWith('/')) base += '/';

    return ParsedPiwigoUrl(
      baseUrl: base,
      categoryId: categoryId,
      slug: slug,
    );
  }
}
