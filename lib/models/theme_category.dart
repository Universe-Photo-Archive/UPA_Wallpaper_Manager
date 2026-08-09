class ThemeCategory {
  final int id;
  final String name;
  final String nameRaw;
  final String url;

  /// Total number of images including sub-albums (Piwigo `total_nb_images`).
  final int imageCount;

  /// Number of images directly inside this category, excluding sub-albums
  /// (Piwigo `nb_images`). Used to decide whether images must be fetched
  /// recursively.
  final int directImageCount;

  final String? thumbnailUrl;

  /// Base URL of the Piwigo source this category comes from
  /// (e.g. "https://universe-photo-archive.eu/gallery/").
  final String sourceBaseUrl;

  /// True when this theme was added manually by the user (and can be removed
  /// via the "Manage themes" dialog). False for themes coming from the
  /// default themes config (shipped or pulled from GitHub).
  final bool isUserAdded;

  /// The original URL the user pasted when adding this theme. Only set when
  /// [isUserAdded] is true.
  final String? originalUrl;

  ThemeCategory({
    required this.id,
    required this.name,
    required this.nameRaw,
    required this.url,
    required this.imageCount,
    int? directImageCount,
    this.thumbnailUrl,
    required this.sourceBaseUrl,
    this.isUserAdded = false,
    this.originalUrl,
  }) : directImageCount = directImageCount ?? imageCount;

  /// True when fetching this category's images requires `recursive=true`
  /// (photos live in sub-albums, e.g. "Thomas Pesquet" -> Mission Alpha +
  /// Mission Proxima). User-added themes always recurse so that adding a
  /// parent album yields the photos of its children.
  bool get needsRecursiveFetch => isUserAdded || imageCount > directImageCount;

  /// Friendly display name: extracts the English part before parentheses,
  /// or the full name if no parentheses are found.
  String get displayName {
    final raw = nameRaw;
    final parenIdx = raw.indexOf('(');
    if (parenIdx > 0) {
      return raw.substring(0, parenIdx).trim();
    }
    return raw;
  }

  factory ThemeCategory.fromPiwigoJson(
    Map<String, dynamic> json, {
    required String sourceBaseUrl,
    bool isUserAdded = false,
    String? originalUrl,
  }) {
    final id = _asInt(json['id']);
    if (id == null) {
      throw FormatException('Piwigo category missing valid id: ${json['id']}');
    }
    // Prefer total_nb_images (count including sub-albums) over nb_images
    // (only direct children). For leaf categories the two are equal; for
    // a parent like "Thomas Pesquet" (nb_images=0, total_nb_images=2138)
    // this is what makes the theme look populated instead of empty.
    final total = _asInt(json['total_nb_images']);
    final direct = _asInt(json['nb_images']);
    final count = (total != null && total > 0)
        ? total
        : (direct ?? total ?? 0);

    return ThemeCategory(
      id: id,
      name: json['name'] as String? ?? '',
      nameRaw: json['name_raw'] as String? ?? json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      imageCount: count,
      directImageCount: direct ?? 0,
      thumbnailUrl: json['tn_url'] as String?,
      sourceBaseUrl: sourceBaseUrl,
      isUserAdded: isUserAdded,
      originalUrl: originalUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameRaw': nameRaw,
        'url': url,
        'imageCount': imageCount,
        'directImageCount': directImageCount,
        'thumbnailUrl': thumbnailUrl,
        'sourceBaseUrl': sourceBaseUrl,
        'isUserAdded': isUserAdded,
        'originalUrl': originalUrl,
      };

  factory ThemeCategory.fromJson(Map<String, dynamic> json) {
    return ThemeCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      nameRaw: json['nameRaw'] as String? ?? json['name'] as String,
      url: json['url'] as String,
      imageCount: json['imageCount'] as int? ?? 0,
      directImageCount: json['directImageCount'] as int?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      sourceBaseUrl: json['sourceBaseUrl'] as String? ?? '',
      isUserAdded: json['isUserAdded'] as bool? ?? false,
      originalUrl: json['originalUrl'] as String?,
    );
  }

  ThemeCategory copyWith({
    int? imageCount,
    int? directImageCount,
    String? thumbnailUrl,
  }) {
    return ThemeCategory(
      id: id,
      name: name,
      nameRaw: nameRaw,
      url: url,
      imageCount: imageCount ?? this.imageCount,
      directImageCount: directImageCount ?? this.directImageCount,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      sourceBaseUrl: sourceBaseUrl,
      isUserAdded: isUserAdded,
      originalUrl: originalUrl,
    );
  }

  /// Stable identity that mixes [sourceBaseUrl] and [id] so that two
  /// categories with the same numeric id coming from different Piwigo
  /// instances are not considered equal.
  String get uniqueKey => '$sourceBaseUrl#$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeCategory && uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;

  @override
  String toString() => 'ThemeCategory($id, $displayName, $imageCount images)';
}

/// Helper: tolerates Piwigo instances that serialize numeric fields as String.
int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
