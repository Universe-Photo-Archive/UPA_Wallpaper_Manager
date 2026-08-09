class WallpaperImage {
  final int id;
  final String filename;
  final String pageUrl;
  final int? width;
  final int? height;
  final Map<String, ImageDerivative> derivatives;

  /// Persisted download URL (survives JSON round-trip even without derivatives)
  String? _cachedFullSizeUrl;

  /// Cache tracking
  bool isDownloaded;
  String? localPath;
  bool isDisplayed;
  int displayCount;
  DateTime? lastDisplayed;

  WallpaperImage({
    required this.id,
    required this.filename,
    required this.pageUrl,
    this.width,
    this.height,
    required this.derivatives,
    String? cachedFullSizeUrl,
    this.isDownloaded = false,
    this.localPath,
    this.isDisplayed = false,
    this.displayCount = 0,
    this.lastDisplayed,
  }) : _cachedFullSizeUrl = cachedFullSizeUrl;

  /// Best URL for full-size wallpaper download.
  /// Prefers live derivatives, falls back to persisted URL from previous session.
  String get fullSizeUrl {
    for (final key in ['xxlarge', 'xlarge', 'large', 'medium', 'small']) {
      if (derivatives.containsKey(key)) {
        final url = derivatives[key]!.url;
        _cachedFullSizeUrl = url;
        return url;
      }
    }
    if (derivatives.values.isNotEmpty) {
      final url = derivatives.values.last.url;
      _cachedFullSizeUrl = url;
      return url;
    }
    return _cachedFullSizeUrl ?? pageUrl;
  }

  /// URL for thumbnail/preview
  String get thumbnailUrl {
    for (final key in ['square', 'thumb', 'xsmall', '2small', 'small']) {
      if (derivatives.containsKey(key)) {
        return derivatives[key]!.url;
      }
    }
    return derivatives.values.isNotEmpty
        ? derivatives.values.first.url
        : pageUrl;
  }

  /// URL for medium preview (gallery grid)
  String get mediumUrl {
    for (final key in ['medium', 'small', 'large']) {
      if (derivatives.containsKey(key)) {
        return derivatives[key]!.url;
      }
    }
    return thumbnailUrl;
  }

  factory WallpaperImage.fromPiwigoJson(Map<String, dynamic> json) {
    final derivativesJson =
        json['derivatives'] as Map<String, dynamic>? ?? {};
    final derivatives = <String, ImageDerivative>{};
    derivativesJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        derivatives[key] = ImageDerivative.fromJson(value);
      }
    });

    final id = _asInt(json['id']);
    if (id == null) {
      throw FormatException('Piwigo image missing valid id: ${json['id']}');
    }

    return WallpaperImage(
      id: id,
      filename: json['file'] as String? ?? 'unknown.jpg',
      pageUrl: json['page_url'] as String? ??
          json['element_url'] as String? ??
          '',
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      derivatives: derivatives,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'pageUrl': pageUrl,
        'width': width,
        'height': height,
        'cachedFullSizeUrl': fullSizeUrl,
        'thumbnailUrl': thumbnailUrl,
        'isDownloaded': isDownloaded,
        'localPath': localPath,
        'isDisplayed': isDisplayed,
        'displayCount': displayCount,
        'lastDisplayed': lastDisplayed?.toIso8601String(),
      };

  factory WallpaperImage.fromJson(Map<String, dynamic> json) {
    return WallpaperImage(
      id: json['id'] as int,
      filename: json['filename'] as String,
      pageUrl: json['pageUrl'] as String? ?? '',
      width: json['width'] as int?,
      height: json['height'] as int?,
      derivatives: {},
      cachedFullSizeUrl: json['cachedFullSizeUrl'] as String? ??
          json['fullSizeUrl'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      localPath: json['localPath'] as String?,
      isDisplayed: json['isDisplayed'] as bool? ?? false,
      displayCount: json['displayCount'] as int? ?? 0,
      lastDisplayed: json['lastDisplayed'] != null
          ? DateTime.tryParse(json['lastDisplayed'] as String)
          : null,
    );
  }

  /// Refresh URL data from a fresh API image while keeping cache state.
  void mergeApiData(WallpaperImage apiImage) {
    if (apiImage.derivatives.isNotEmpty) {
      derivatives
        ..clear()
        ..addAll(apiImage.derivatives);
    }
    _cachedFullSizeUrl = apiImage.fullSizeUrl;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WallpaperImage && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ImageDerivative {
  final String url;
  final int? width;
  final int? height;

  const ImageDerivative({
    required this.url,
    this.width,
    this.height,
  });

  factory ImageDerivative.fromJson(Map<String, dynamic> json) {
    return ImageDerivative(
      url: json['url'] as String? ?? '',
      width: _asInt(json['width']),
      height: _asInt(json['height']),
    );
  }
}

/// Helper: many Piwigo instances serialize numeric fields inconsistently
/// (sometimes as int, sometimes as String). This converts both safely.
int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
