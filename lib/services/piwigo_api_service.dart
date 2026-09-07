import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/theme_category.dart';
import '../models/theme_source.dart';
import '../models/wallpaper_image.dart';

/// Multi-source Piwigo API client.
///
/// Each call accepts a [baseUrl] (Piwigo gallery root, e.g.
/// `https://example.com/gallery/`) so the same client can talk to several
/// Piwigo instances (the default UPA gallery + user-added galleries).
class PiwigoApiService {
  /// The historical default UPA gallery base — kept for backward-compat
  /// with code that does not yet pass a baseUrl explicitly.
  static const String defaultUpaBaseUrl =
      'https://universe-photo-archive.eu/gallery/';

  /// Historical default category id used as a fallback when callers do not
  /// configure a source.
  static const int defaultUpaRootCategoryId = 717;

  /// Tag marking the photos the gallery does not want on a phone.
  static const String noMobileTag = 'NoMobile';

  /// Appended to the browser user-agent so a gallery owner reading their
  /// access log can tell the app apart from a real browser — and tell which
  /// build is talking to them. Set once at start-up.
  static String appIdentifier = 'UPA-Wallpaper-Manager';

  /// Some third-party Piwigo hosts (university, institutional galleries)
  /// answer 403 to anything that does not look like a browser.
  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  late final Dio _dio;

  /// Ids kept out of every listing, set by the app when the "NoMobile"
  /// option is on. Only ever applied to the UPA gallery: someone else's
  /// Piwigo has no reason to know about our tag, and an id collision there
  /// would hide an innocent photo.
  Set<int> hiddenImageIds = const {};

  /// True for the galleries hosted by Universe Photo Archive.
  static bool isUpaGallery(String baseUrl) => isUpaGalleryUrl(baseUrl);

  /// Deepest the app will page into one album.
  ///
  /// Paging is what costs the gallery: every page makes the server count
  /// again from the first photo of the album, so page 40 of a large album is
  /// far more expensive than page 1. Ten pages is already five thousand
  /// photos, more variety than a slideshow can use.
  static const int maxPagesPerTheme = 10;

  /// Beyond this many photos an album is not a theme but a whole gallery.
  /// One page is taken from it and the rest is left alone, because deep
  /// paging over such an album can keep a database busy for minutes.
  static const int hugeAlbumThreshold = 20000;

  /// An album this big can only be the root of a gallery; refusing it when
  /// the user adds it is kinder than letting them break their own server.
  static const int refuseAlbumThreshold = 200000;

  /// Shortest gap between two requests leaving the app.
  ///
  /// A dozen phones each firing a burst of listings at the same shared
  /// gallery is what turns a slow query into an outage.
  static const Duration _minRequestGap = Duration(milliseconds: 400);

  /// Consecutive failures after which a gallery is left alone for a while.
  static const int _failuresBeforeBackingOff = 2;
  static const Duration _firstBackOff = Duration(minutes: 5);
  static const Duration _maxBackOff = Duration(minutes: 60);

  Future<void> _gate = Future<void>.value();
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, _HostHealth> _health = {};

  PiwigoApiService({double rateLimitSeconds = 1.0, int timeoutSeconds = 30}) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: timeoutSeconds),
        receiveTimeout: Duration(seconds: timeoutSeconds),
        responseType: ResponseType.plain,
        followRedirects: true,
        headers: {
          'User-Agent': _browserUserAgent,
          'Accept': 'application/json,text/plain,*/*',
        },
      ),
    );

    // Everything the app asks of a gallery goes through here: spacing the
    // requests out, and standing back when the gallery is in trouble.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['User-Agent'] = '$_browserUserAgent $appIdentifier';
          final host = options.uri.host;
          final until = _health[host]?.silentUntil;
          if (until != null && DateTime.now().isBefore(until)) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message:
                    'Gallery $host is unwell; not asking again before '
                    '${until.toIso8601String()}',
              ),
            );
            return;
          }
          await _spaceOutRequest();
          handler.next(options);
        },
        onResponse: (response, handler) {
          _health.remove(response.requestOptions.uri.host);
          handler.next(response);
        },
        onError: (error, handler) {
          // A rejection of our own making must not count against the host.
          if (error.type != DioExceptionType.cancel) {
            _noteFailure(error.requestOptions.uri.host);
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Holds each request back until at least [_minRequestGap] has passed since
  /// the previous one left.
  Future<void> _spaceOutRequest() {
    final previous = _gate;
    final mine = Completer<void>();
    _gate = mine.future;

    return previous.then((_) async {
      try {
        final since = DateTime.now().difference(_lastRequestAt);
        final wait = _minRequestGap - since;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        _lastRequestAt = DateTime.now();
      } finally {
        // Whatever happens, the next request must not wait forever.
        mine.complete();
      }
    });
  }

  void _noteFailure(String host) {
    final health = _health.putIfAbsent(host, _HostHealth.new);
    health.failures += 1;
    if (health.failures < _failuresBeforeBackingOff) return;

    health.backOff = health.silentUntil == null
        ? _firstBackOff
        : Duration(
            seconds: (health.backOff.inSeconds * 2).clamp(
              0,
              _maxBackOff.inSeconds,
            ),
          );
    health.silentUntil = DateTime.now().add(health.backOff);
    _log.w(
      'Gallery $host failed ${health.failures} times in a row — leaving it '
      'alone for ${health.backOff.inMinutes} min',
    );
  }

  /// Forgets a gallery's failures, for when the user asks for something
  /// themselves and deserves a real attempt rather than a stale refusal.
  void forgetFailures([String? baseUrl]) {
    if (baseUrl == null) {
      _health.clear();
      return;
    }
    _health.remove(Uri.tryParse(baseUrl)?.host ?? baseUrl);
  }

  Map<String, dynamic> _parseJson(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      return json.decode(raw) as Map<String, dynamic>;
    }
    throw FormatException('Unexpected response type: ${raw.runtimeType}');
  }

  String _wsUrl(String baseUrl) {
    var b = baseUrl;
    if (!b.endsWith('/')) b += '/';
    return '${b}ws.php';
  }

  /// Tests connection to a Piwigo gallery.
  Future<bool> testConnection({String baseUrl = defaultUpaBaseUrl}) async {
    try {
      final response = await _dio.get(
        _wsUrl(baseUrl),
        queryParameters: {'format': 'json', 'method': 'pwg.getVersion'},
      );
      return response.statusCode == 200;
    } catch (e) {
      _log.w('Connection test failed for $baseUrl: $e');
      return false;
    }
  }

  /// True when the gallery host answers but refuses the Piwigo web-service
  /// (HTTP 401/403). Typical of institutional sites that hide `ws.php`.
  Future<bool> isApiBlocked(String baseUrl) async {
    try {
      final response = await _dio.get(
        _wsUrl(baseUrl),
        queryParameters: {'format': 'json', 'method': 'pwg.getVersion'},
        options: Options(validateStatus: (code) => code != null && code < 500),
      );
      return response.statusCode == 401 || response.statusCode == 403;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      return code == 401 || code == 403;
    } catch (_) {
      return false;
    }
  }

  /// Loads all themes for a given [PiwigoSource]. When [PiwigoSource.recursive]
  /// is true the [rootCategoryId] is treated as a parent and all
  /// sub-categories are returned (excluding the parent itself). When false,
  /// only [rootCategoryId] is returned (one theme).
  Future<List<ThemeCategory>> getThemesFromSource(
    PiwigoSource source, {
    bool isUserAdded = false,
  }) async {
    try {
      final response = await _dio.get(
        _wsUrl(source.baseUrl),
        queryParameters: {
          'format': 'json',
          'method': 'pwg.categories.getList',
          'cat_id': source.rootCategoryId.toString(),
          'recursive': source.recursive ? 'true' : 'false',
        },
      );

      final jsonData = _parseJson(response);

      if (jsonData['stat'] != 'ok') {
        _log.e(
          'Piwigo API error: ${jsonData['stat']} - '
          '${jsonData['message'] ?? ""}',
        );
        return [];
      }

      final categories =
          jsonData['result']?['categories'] as List<dynamic>? ?? [];

      final themes = <ThemeCategory>[];
      for (final c in categories) {
        if (c is! Map<String, dynamic>) continue;
        final id = c['id'];
        final intId = id is int ? id : int.tryParse(id.toString());
        if (intId == null) continue;

        if (source.recursive) {
          // Skip the parent category itself; only sub-categories are themes.
          if (intId == source.rootCategoryId) continue;
        } else {
          // We only want exactly the requested category.
          if (intId != source.rootCategoryId) continue;
        }

        themes.add(
          ThemeCategory.fromPiwigoJson(
            c,
            sourceBaseUrl: source.baseUrl,
            isUserAdded: isUserAdded,
            originalUrl: source.originalUrl,
          ),
        );
      }

      _log.i(
        'Loaded ${themes.length} theme(s) from ${source.baseUrl} (cat=${source.rootCategoryId}, recursive=${source.recursive})',
      );
      return themes;
    } catch (e, stack) {
      _log.e(
        'Failed to fetch themes for ${source.baseUrl}'
        ' (cat=${source.rootCategoryId}): $e\n$stack',
      );
      return [];
    }
  }

  /// Fetches images for a given category. The [baseUrl] should match
  /// the [ThemeCategory.sourceBaseUrl] of the theme.
  ///
  /// When [recursive] is true the request includes `recursive=true`, which
  /// asks Piwigo to also return photos that live in any descendant album of
  /// [categoryId]. This is what users expect when they add a parent album
  /// (e.g. "Thomas Pesquet" -> includes "Mission Alpha" + "Mission Proxima").
  /// For default themes that already split sub-albums into separate themes
  /// we keep [recursive] = false to avoid double-counting.
  ///
  /// All pages are walked transparently so the caller gets the full image
  /// set even when the gallery contains thousands of photos. [maxPages] is
  /// a safety cap to prevent runaway loops on misbehaving servers.
  Future<List<WallpaperImage>> getThemeImages(
    int categoryId, {
    String baseUrl = defaultUpaBaseUrl,
    int perPage = 500,
    bool recursive = false,
    int maxPages = maxPagesPerTheme,
  }) async {
    final wallpapers = <WallpaperImage>[];
    int page = 0;
    int totalPages = 1;

    while (page < totalPages && page < maxPages) {
      try {
        final response = await _dio.get(
          _wsUrl(baseUrl),
          queryParameters: {
            'format': 'json',
            'method': 'pwg.categories.getImages',
            'cat_id': categoryId.toString(),
            'per_page': perPage.toString(),
            'page': page.toString(),
            if (recursive) 'recursive': 'true',
          },
        );

        final jsonData = _parseJson(response);

        if (jsonData['stat'] != 'ok') {
          _log.e(
            'Piwigo API error fetching images (page $page): '
            '${jsonData['stat']}',
          );
          break;
        }

        final paging = jsonData['result']?['paging'] as Map<String, dynamic>?;
        final images = jsonData['result']?['images'] as List<dynamic>? ?? [];

        // Parse each image independently so a single malformed entry does
        // not break the whole batch. Some third-party Piwigo instances emit
        // non-canonical types (e.g. width as String) for a few images.
        final filtering = hiddenImageIds.isNotEmpty && isUpaGallery(baseUrl);
        for (final img in images) {
          if (img is! Map<String, dynamic>) continue;
          try {
            final parsed = WallpaperImage.fromPiwigoJson(img);
            if (filtering && hiddenImageIds.contains(parsed.id)) continue;
            wallpapers.add(parsed);
          } catch (e) {
            _log.w(
              'Skipping image due to parse error at $baseUrl '
              '(category $categoryId, id=${img['id']}): $e',
            );
          }
        }

        // Determine how many more pages we still need to fetch. Piwigo's
        // paging block contains `count` (items in this page) and
        // `total_count` (all items); some instances also expose `pages`.
        final pagesField = _asInt(paging?['pages']);
        final totalCount = _asInt(paging?['total_count']);
        if (pagesField != null && pagesField > 0) {
          totalPages = pagesField;
        } else if (totalCount != null && totalCount > 0) {
          totalPages = (totalCount + perPage - 1) ~/ perPage;
        } else if (images.length < perPage) {
          // Short page -> this was the last one.
          totalPages = page + 1;
        } else {
          // Full page and no total info -> assume at least one more page.
          totalPages = page + 2;
        }

        // An album of this size is somebody's whole gallery. Walking into it
        // would have the server count past hundreds of thousands of photos
        // on every page, over and over; one page is plenty to rotate on.
        if ((totalCount ?? 0) > hugeAlbumThreshold) {
          _log.w(
            'Category $categoryId at $baseUrl holds $totalCount photos — '
            'keeping the first $perPage and going no further',
          );
          break;
        }

        if (images.isEmpty) break;
        page += 1;
      } catch (e, stack) {
        _log.e(
          'Failed to fetch images page $page for category '
          '$categoryId at $baseUrl: $e\n$stack',
        );
        break;
      }
    }

    if (page >= maxPages) {
      _log.w(
        'Stopped at $maxPages pages for category $categoryId at $baseUrl; '
        'the rest of the album is left unread',
      );
    }

    _log.i(
      'Loaded ${wallpapers.length} images for category $categoryId'
      ' at $baseUrl'
      '${recursive ? " (recursive)" : ""}'
      ' across $page page(s)',
    );

    return wallpapers;
  }

  /// Ids of every photo carrying [tagName].
  ///
  /// Returns null — meaning "do not filter anything" — when the gallery has
  /// no such tag or will not answer. `pwg.categories.getImages` does not
  /// report tags, hence this separate lookup rather than filtering inline.
  Future<Set<int>?> getTaggedImageIds(
    String tagName, {
    String baseUrl = defaultUpaBaseUrl,
    int perPage = 500,
    int maxPages = 100,
  }) async {
    final tagId = await _findTagId(tagName, baseUrl);
    if (tagId == null) return null;

    final ids = <int>{};
    var page = 0;
    while (page < maxPages) {
      try {
        final response = await _dio.get(
          _wsUrl(baseUrl),
          queryParameters: {
            'format': 'json',
            'method': 'pwg.tags.getImages',
            'tag_id': tagId.toString(),
            'per_page': perPage.toString(),
            'page': page.toString(),
          },
        );
        final jsonData = _parseJson(response);
        if (jsonData['stat'] != 'ok') return page == 0 ? null : ids;

        final images = jsonData['result']?['images'] as List<dynamic>? ?? [];
        for (final img in images) {
          if (img is! Map<String, dynamic>) continue;
          final id = _asInt(img['id']);
          if (id != null) ids.add(id);
        }
        if (images.length < perPage) break;
        page += 1;
      } catch (e) {
        _log.w('Tag "$tagName" page $page failed at $baseUrl: $e');
        return page == 0 ? null : ids;
      }
    }

    _log.i('Tag "$tagName" covers ${ids.length} photo(s) at $baseUrl');
    return ids;
  }

  Future<int?> _findTagId(String tagName, String baseUrl) async {
    try {
      final response = await _dio.get(
        _wsUrl(baseUrl),
        queryParameters: {'format': 'json', 'method': 'pwg.tags.getList'},
      );
      final jsonData = _parseJson(response);
      if (jsonData['stat'] != 'ok') return null;

      final tags = jsonData['result']?['tags'] as List<dynamic>? ?? [];
      final wanted = tagName.toLowerCase();
      for (final tag in tags) {
        if (tag is! Map<String, dynamic>) continue;
        final name = (tag['name'] as String? ?? '').toLowerCase();
        final urlName = (tag['url_name'] as String? ?? '').toLowerCase();
        if (name == wanted || urlName == wanted) return _asInt(tag['id']);
      }
      _log.i('No "$tagName" tag at $baseUrl — nothing to hide');
      return null;
    } catch (e) {
      _log.w('Could not list tags at $baseUrl: $e');
      return null;
    }
  }

  /// Validates a parsed Piwigo URL by querying the gallery for that exact
  /// category. Returns the resolved [ThemeCategory] on success, null on
  /// failure (network error, invalid URL, no such category).
  ///
  /// Tries `pwg.categories.getList?cat_id=X` first (which on most Piwigo
  /// instances returns X plus its direct children). Falls back to
  /// `pwg.categories.getImages` to verify existence and grab a count.
  Future<ThemeCategory?> resolveCategory(ParsedPiwigoUrl url) async {
    // Attempt 1: getList with cat_id=X
    try {
      final response = await _dio.get(
        _wsUrl(url.baseUrl),
        queryParameters: {
          'format': 'json',
          'method': 'pwg.categories.getList',
          'cat_id': url.categoryId.toString(),
        },
      );
      final jsonData = _parseJson(response);
      if (jsonData['stat'] == 'ok') {
        final categories =
            jsonData['result']?['categories'] as List<dynamic>? ?? [];
        for (final c in categories) {
          if (c is! Map<String, dynamic>) continue;
          final id = c['id'];
          final intId = id is int ? id : int.tryParse(id.toString());
          if (intId == url.categoryId) {
            return ThemeCategory.fromPiwigoJson(
              c,
              sourceBaseUrl: url.baseUrl,
              isUserAdded: true,
              originalUrl: _rebuildUrl(url),
            );
          }
        }
      }
    } catch (e) {
      _log.w('resolveCategory getList failed: $e');
    }

    // Attempt 2: verify via getImages (returns paging.count for image count).
    // Use recursive=true so parent categories with no direct images but
    // containing sub-albums (e.g. "Thomas Pesquet" -> Mission Alpha +
    // Mission Proxima) report a non-zero count instead of "0 photos".
    try {
      final response = await _dio.get(
        _wsUrl(url.baseUrl),
        queryParameters: {
          'format': 'json',
          'method': 'pwg.categories.getImages',
          'cat_id': url.categoryId.toString(),
          'per_page': '1',
          'recursive': 'true',
        },
      );
      final jsonData = _parseJson(response);
      if (jsonData['stat'] != 'ok') return null;

      final paging = jsonData['result']?['paging'] as Map<String, dynamic>?;
      final count =
          _asInt(paging?['count']) ?? _asInt(paging?['total_count']) ?? 0;

      final fallbackName = url.slug != null
          ? url.slug!
                .split(RegExp(r'[-_]'))
                .where((s) => s.isNotEmpty)
                .map((s) => s[0].toUpperCase() + s.substring(1))
                .join(' ')
          : 'Album ${url.categoryId}';

      return ThemeCategory(
        id: url.categoryId,
        name: fallbackName,
        nameRaw: fallbackName,
        url: _rebuildUrl(url),
        imageCount: count,
        sourceBaseUrl: url.baseUrl,
        isUserAdded: true,
        originalUrl: _rebuildUrl(url),
      );
    } catch (e, stack) {
      _log.e('resolveCategory getImages fallback failed: $e\n$stack');
      return null;
    }
  }

  String _rebuildUrl(ParsedPiwigoUrl url) {
    final tail = url.slug != null && url.slug!.isNotEmpty
        ? '${url.categoryId}-${url.slug}'
        : '${url.categoryId}';
    return '${url.baseUrl}index.php?/category/$tail';
  }

  void updateOptions({double? rateLimitSeconds, int? timeoutSeconds}) {
    if (timeoutSeconds != null) {
      _dio.options.connectTimeout = Duration(seconds: timeoutSeconds);
      _dio.options.receiveTimeout = Duration(seconds: timeoutSeconds);
    }
  }
}

/// How a gallery has been behaving lately.
class _HostHealth {
  int failures = 0;
  DateTime? silentUntil;
  Duration backOff = Duration.zero;
}

/// Helper: tolerates Piwigo instances that serialize numeric fields as String.
int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
