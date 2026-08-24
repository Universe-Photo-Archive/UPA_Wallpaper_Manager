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

/// How a local theme decides which images belong to it.
enum LocalThemeKind {
  /// Every image inside the chosen folder, followed over time: photos added
  /// later show up, photos deleted disappear.
  folder,

  /// A hand-picked list of images taken from one or more folders.
  custom,
}

/// Images the user owns, exposed as a theme.
///
/// Nothing is ever copied. On desktop the references are absolute file paths;
/// on Android they are `content://` document URIs, and [roots] holds the
/// folders the user granted lasting access to — one grant covers everything
/// inside, which is why even a hand-picked theme is built by first choosing a
/// folder and then ticking photos within it.
class LocalSource {
  /// Stable identity, independent of the folder so a theme can be renamed or
  /// draw from several folders.
  final String id;

  final LocalThemeKind kind;

  /// Display name shown in the theme lists.
  final String name;

  /// Folders this theme may read from. Desktop stores paths, Android stores
  /// document tree URIs whose permission has been persisted.
  final List<String> roots;

  /// [LocalThemeKind.custom] only: the chosen images, as file paths or
  /// document URIs. Ignored for folder themes, which enumerate [roots].
  final List<String> items;

  const LocalSource({
    required this.id,
    required this.kind,
    required this.name,
    this.roots = const [],
    this.items = const [],
  });

  /// Marker prefix used in [ThemeCategory.sourceBaseUrl] so the rest of the
  /// app can detect "this theme is local, do not call Piwigo".
  static const String urlScheme = 'local://';

  String get sourceBaseUrl => '$urlScheme$id';
  String get uniqueKey => sourceBaseUrl;

  /// Synthetic numeric id, still expected by [ThemeCategory].
  int get numericId => id.hashCode & 0x7fffffff;

  bool get isFolder => kind == LocalThemeKind.folder;

  /// Extracts the theme id from a [ThemeCategory.sourceBaseUrl].
  static String? idFromSourceBaseUrl(String sourceBaseUrl) {
    if (!sourceBaseUrl.startsWith(urlScheme)) return null;
    final id = sourceBaseUrl.substring(urlScheme.length);
    return id.isEmpty ? null : id;
  }

  factory LocalSource.fromJson(Map<String, dynamic> json) {
    return LocalSource(
      id: json['id'] as String? ?? '',
      kind: (json['kind'] as String?) == 'custom'
          ? LocalThemeKind.custom
          : LocalThemeKind.folder,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Galerie locale',
      roots: (json['roots'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind == LocalThemeKind.custom ? 'custom' : 'folder',
        'name': name,
        'roots': roots,
        'items': items,
      };

  LocalSource copyWith({
    String? name,
    List<String>? roots,
    List<String>? items,
  }) =>
      LocalSource(
        id: id,
        kind: kind,
        name: name ?? this.name,
        roots: roots ?? this.roots,
        items: items ?? this.items,
      );

  /// Last path segment of a folder reference, used to name folder themes.
  static String folderDisplayName(String root) {
    var clean = Uri.decodeComponent(root).replaceAll('\\', '/').trimRight();
    // Document tree URIs end with something like ".../tree/primary:Pictures".
    final colon = clean.lastIndexOf(':');
    if (colon >= 0 && clean.contains('/tree/')) {
      clean = clean.substring(colon + 1);
    }
    final parts = clean.split('/').where((p) => p.trim().isNotEmpty).toList();
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
