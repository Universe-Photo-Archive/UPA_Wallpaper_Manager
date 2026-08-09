import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import '../models/theme_source.dart';

/// Manages the persistence of theme configuration files:
///
///   - themes_default.json (bundled in assets, optionally refreshed from
///     GitHub on every app start)
///   - themes_user.json (themes added manually by the user, never overwritten
///     by an update of the default config)
///
/// Both files are stored in the application support directory so they
/// survive app updates.
class ThemesConfigService {
  static const String _defaultBundleAssetPath =
      'assets/config/themes_default.json';
  static const String _defaultFileName = 'themes_default.json';
  static const String _userFileName = 'themes_user.json';

  /// Where to fetch a possibly-newer copy of the default config from GitHub.
  /// Read from the bundled config (`githubUrl` field) but a hard fallback is
  /// kept here for safety.
  static const String _fallbackGithubUrl =
      'https://raw.githubusercontent.com/Universe-Photo-Archive/UPA_Wallpaper_Manager/main/config/themes_default.json';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'UPA-Wallpaper-Manager'},
  ));

  late Directory _configDir;
  Map<String, dynamic> _defaultConfig = {};
  Map<String, dynamic> _userConfig = {
    'version': 1,
    'piwigoSources': [],
    'localSources': [],
  };

  Future<void> init() async {
    final supportDir = await getApplicationSupportDirectory();
    _configDir = Directory('${supportDir.path}/config');
    if (!_configDir.existsSync()) {
      await _configDir.create(recursive: true);
    }

    await _loadDefaultConfig();
    await _loadUserConfig();
  }

  // ---------- DEFAULT CONFIG ----------

  File get _defaultFile => File('${_configDir.path}/$_defaultFileName');
  File get _userFile => File('${_configDir.path}/$_userFileName');

  Future<void> _loadDefaultConfig() async {
    Map<String, dynamic>? diskConfig;
    if (await _defaultFile.exists()) {
      try {
        diskConfig = json.decode(await _defaultFile.readAsString())
            as Map<String, dynamic>;
      } catch (e) {
        _log.w('Failed to read on-disk default config: $e — using bundle');
      }
    }

    Map<String, dynamic>? bundleConfig;
    try {
      final raw = await rootBundle.loadString(_defaultBundleAssetPath);
      bundleConfig = json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      _log.e('Failed to load bundled default themes config: $e');
    }

    // The disk copy may be stale (written by an older app version and never
    // refreshed because the GitHub fetch fails). Prefer whichever of the
    // bundled / on-disk configs is the most recent.
    if (diskConfig != null &&
        (bundleConfig == null || !_isNewerConfig(bundleConfig, diskConfig))) {
      _defaultConfig = diskConfig;
      _log.i('Default themes config loaded from disk');
      return;
    }

    if (bundleConfig != null) {
      _defaultConfig = bundleConfig;
      try {
        await _defaultFile.writeAsString(json.encode(_defaultConfig));
      } catch (e) {
        _log.w('Failed to persist bundled default config: $e');
      }
      _log.i(diskConfig == null
          ? 'Default themes config copied from bundle'
          : 'Default themes config updated from newer bundle '
              '(version ${bundleConfig['version']})');
      return;
    }

    _defaultConfig = {'version': 1, 'piwigoSources': []};
  }

  /// True when config [a] is strictly more recent than [b], comparing the
  /// [version] field first, then [lastUpdated] (ISO-8601 strings compare
  /// lexicographically).
  bool _isNewerConfig(Map<String, dynamic> a, Map<String, dynamic> b) {
    final versionA = a['version'] as int? ?? 0;
    final versionB = b['version'] as int? ?? 0;
    if (versionA != versionB) return versionA > versionB;
    final updatedA = a['lastUpdated'] as String? ?? '';
    final updatedB = b['lastUpdated'] as String? ?? '';
    return updatedA.compareTo(updatedB) > 0;
  }

  Future<void> _loadUserConfig() async {
    if (await _userFile.exists()) {
      try {
        _userConfig = json.decode(await _userFile.readAsString())
            as Map<String, dynamic>;
        return;
      } catch (e) {
        _log.w('Failed to read user themes config: $e — resetting');
      }
    }
    _userConfig = {
      'version': 1,
      'piwigoSources': [],
      'localSources': [],
    };
    await _saveUserConfig();
  }

  Future<void> _saveUserConfig() async {
    try {
      await _userFile.writeAsString(json.encode(_userConfig));
    } catch (e) {
      _log.e('Failed to save user themes config: $e');
    }
  }

  // ---------- GITHUB UPDATE ----------

  /// Fetches the latest default config from GitHub. If newer (by [version]
  /// field, or just different content), it replaces the local default file.
  ///
  /// User-added themes are never modified by this operation.
  Future<bool> refreshDefaultConfigFromGitHub() async {
    final url = _defaultConfig['githubUrl'] as String? ?? _fallbackGithubUrl;
    try {
      _log.i('Checking for default themes config update at $url');
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode != 200 || response.data == null) {
        _log.w('GitHub fetch returned status ${response.statusCode}');
        return false;
      }
      final remote = json.decode(response.data!) as Map<String, dynamic>;
      final remoteVersion = remote['version'] as int? ?? 0;
      final localVersion = _defaultConfig['version'] as int? ?? 0;

      // Update if remote version is strictly newer, OR if lastUpdated changed
      // (so themes can be added without bumping the version field).
      final remoteUpdated = remote['lastUpdated'] as String? ?? '';
      final localUpdated = _defaultConfig['lastUpdated'] as String? ?? '';

      final shouldUpdate =
          remoteVersion > localVersion || remoteUpdated != localUpdated;

      if (!shouldUpdate) {
        _log.i('Default themes config is up-to-date');
        return false;
      }

      _defaultConfig = remote;
      await _defaultFile.writeAsString(json.encode(remote));
      _log.i('Default themes config updated from GitHub '
          '(version $remoteVersion, lastUpdated $remoteUpdated)');
      return true;
    } catch (e) {
      _log.w('Could not refresh default themes config from GitHub: $e');
      return false;
    }
  }

  // ---------- ACCESSORS ----------

  /// All piwigo sources from the default config.
  List<PiwigoSource> get defaultPiwigoSources {
    final list = _defaultConfig['piwigoSources'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(PiwigoSource.fromJson)
        .toList();
  }

  /// All piwigo sources added by the user.
  List<PiwigoSource> get userPiwigoSources {
    final list = _userConfig['piwigoSources'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(PiwigoSource.fromJson)
        .toList();
  }

  /// True when a user source with the same baseUrl + categoryId already exists.
  bool hasUserSource(String baseUrl, int categoryId) {
    final normalized = PiwigoSource(
        baseUrl: baseUrl, rootCategoryId: categoryId, recursive: false);
    return userPiwigoSources.any((s) => s.uniqueKey == normalized.uniqueKey);
  }

  /// Adds a user source and persists.
  Future<void> addUserSource(PiwigoSource source) async {
    final list =
        List<Map<String, dynamic>>.from(userPiwigoSources.map((e) => e.toJson()))
          ..add(source.toJson());
    _userConfig['piwigoSources'] = list;
    await _saveUserConfig();
  }

  /// Removes a user source matching the given baseUrl + categoryId.
  Future<void> removeUserSource(String baseUrl, int categoryId) async {
    final list = userPiwigoSources
        .where((s) =>
            !(s.baseUrl == baseUrl && s.rootCategoryId == categoryId))
        .map((e) => e.toJson())
        .toList();
    _userConfig['piwigoSources'] = list;
    await _saveUserConfig();
  }

  // ---------- LOCAL SOURCES ----------

  /// All local folder sources added by the user.
  List<LocalSource> get userLocalSources {
    final list = _userConfig['localSources'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(LocalSource.fromJson)
        .toList();
  }

  /// True when a local source with the same folder path already exists.
  bool hasLocalSource(String folderPath) {
    return userLocalSources.any((s) => s.folderPath == folderPath);
  }

  /// Adds a local source and persists.
  Future<void> addLocalSource(LocalSource source) async {
    final list =
        List<Map<String, dynamic>>.from(userLocalSources.map((e) => e.toJson()))
          ..add(source.toJson());
    _userConfig['localSources'] = list;
    await _saveUserConfig();
  }

  /// Removes a local source matching the given folder path.
  Future<void> removeLocalSource(String folderPath) async {
    final list = userLocalSources
        .where((s) => s.folderPath != folderPath)
        .map((e) => e.toJson())
        .toList();
    _userConfig['localSources'] = list;
    await _saveUserConfig();
  }

  /// Updates a single user source's cached metadata in place.
  Future<void> updateUserSourceCachedMeta(
    String baseUrl,
    int categoryId, {
    String? cachedName,
    int? cachedImageCount,
    String? cachedThumbnailUrl,
  }) async {
    final updated = <Map<String, dynamic>>[];
    for (final s in userPiwigoSources) {
      if (s.baseUrl == baseUrl && s.rootCategoryId == categoryId) {
        updated.add(PiwigoSource(
          baseUrl: s.baseUrl,
          rootCategoryId: s.rootCategoryId,
          recursive: s.recursive,
          originalUrl: s.originalUrl,
          cachedName: cachedName ?? s.cachedName,
          cachedImageCount: cachedImageCount ?? s.cachedImageCount,
          cachedThumbnailUrl: cachedThumbnailUrl ?? s.cachedThumbnailUrl,
        ).toJson());
      } else {
        updated.add(s.toJson());
      }
    }
    _userConfig['piwigoSources'] = updated;
    await _saveUserConfig();
  }
}
