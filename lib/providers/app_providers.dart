import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/app_config.dart';
import '../models/screen_info.dart';
import '../models/theme_category.dart';
import '../models/theme_source.dart';
import '../models/wallpaper_image.dart';
import '../services/cache_service.dart';
import '../services/config_service.dart';
import '../services/local_gallery_service.dart';
import '../services/log_service.dart';
import '../services/piwigo_api_service.dart';
import '../services/rotation_service.dart';
import '../services/themes_config_service.dart';
import '../services/update_service.dart';
import '../platform/lockscreen_channel.dart';
import '../platform/media_access_channel.dart';
import '../platform/wallpaper_channel.dart';

// --- Singletons ---

final configServiceProvider = Provider<ConfigService>((ref) {
  throw UnimplementedError('Must be overridden at app startup');
});

final cacheServiceProvider = Provider<CacheService>((ref) {
  throw UnimplementedError('Must be overridden at app startup');
});

final logServiceProvider = Provider<LogService>((ref) {
  throw UnimplementedError('Must be overridden at app startup');
});

final piwigoApiProvider = Provider<PiwigoApiService>((ref) {
  return PiwigoApiService(
    rateLimitSeconds: 1.0,
    timeoutSeconds: 30,
  );
});

final rotationServiceProvider = Provider<RotationService>((ref) {
  throw UnimplementedError('Must be overridden at app startup');
});

final themesConfigServiceProvider = Provider<ThemesConfigService>((ref) {
  throw UnimplementedError('Must be overridden at app startup');
});

final localGalleryServiceProvider = Provider<LocalGalleryService>((ref) {
  return LocalGalleryService();
});

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

// --- Config ---

final configProvider = StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  final configService = ref.watch(configServiceProvider);
  return ConfigNotifier(configService);
});

class ConfigNotifier extends StateNotifier<AppConfig> {
  final ConfigService _service;

  ConfigNotifier(this._service) : super(_service.config);

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    state = updater(state);
    await _service.update((_) => state);
  }
}

// --- Connectivity ---

final isOnlineProvider = StateProvider<bool>((ref) => false);

// --- Lockscreen support ---

/// Result of checking whether the lockscreen feature can be used on the
/// running machine. Both [isAdmin] and [isEditionSupported] must be true for
/// the feature to actually work; the UI uses [isSupported] to gate the toggle.
class LockscreenSupport {
  final bool isAdmin;
  final bool isEditionSupported;

  const LockscreenSupport({
    required this.isAdmin,
    required this.isEditionSupported,
  });

  bool get isSupported => isAdmin && isEditionSupported;

  static const LockscreenSupport unknown =
      LockscreenSupport(isAdmin: false, isEditionSupported: false);
}

/// Async one-shot probe of the platform lockscreen capabilities. Computed
/// once at startup and reused everywhere via [lockscreenSupportProvider].
final lockscreenSupportProvider =
    FutureProvider<LockscreenSupport>((ref) async {
  if (Platform.isAndroid) {
    // Android supports FLAG_LOCK wallpapers since Nougat; there is no
    // elevation / edition requirement like on Windows.
    final supported = await LockscreenChannel.isSupported();
    return LockscreenSupport(isAdmin: true, isEditionSupported: supported);
  }
  if (!Platform.isWindows) {
    return const LockscreenSupport(isAdmin: false, isEditionSupported: false);
  }
  final results = await Future.wait([
    LockscreenChannel.isAdmin(),
    LockscreenChannel.isWindowsEditionSupported(),
  ]);
  return LockscreenSupport(
    isAdmin: results[0],
    isEditionSupported: results[1],
  );
});

// --- Themes ---

final themesProvider =
    StateNotifierProvider<ThemesNotifier, List<ThemeCategory>>((ref) {
  return ThemesNotifier();
});

class ThemesNotifier extends StateNotifier<List<ThemeCategory>> {
  ThemesNotifier() : super([]);

  void setThemes(List<ThemeCategory> themes) => state = themes;

  void addTheme(ThemeCategory theme) {
    if (state.any((t) => t.uniqueKey == theme.uniqueKey)) return;
    state = [...state, theme];
  }

  void removeTheme(ThemeCategory theme) {
    state = state.where((t) => t.uniqueKey != theme.uniqueKey).toList();
  }

  /// Swaps a theme for an updated version, keeping its position.
  void replaceTheme(ThemeCategory theme) {
    final index = state.indexWhere((t) => t.uniqueKey == theme.uniqueKey);
    if (index < 0) {
      addTheme(theme);
      return;
    }
    final updated = [...state];
    updated[index] = theme;
    state = updated;
  }

  /// Returns only user-added themes (eligible for removal in the UI).
  List<ThemeCategory> get userThemes =>
      state.where((t) => t.isUserAdded).toList();
}

/// High-level orchestration for adding / removing themes from the gallery
/// dropdown. Encapsulates persistence (themes_user.json), API calls and
/// state propagation.
final themesManagerProvider = Provider<ThemesManager>((ref) {
  return ThemesManager(ref);
});

class ThemesManager {
  final Ref _ref;
  ThemesManager(this._ref);

  /// Validates the URL, fetches the category, persists it, and pushes it
  /// into [themesProvider]. Returns null on success, or a localizable error
  /// key (e.g. 'invalidUrl', 'alreadyExists', 'addFailed').
  Future<String?> addPiwigoThemeFromUrl(String rawUrl) async {
    final parsed = ParsedPiwigoUrl.parse(rawUrl);
    if (parsed == null) return 'invalidUrl';

    final cfg = _ref.read(themesConfigServiceProvider);
    if (cfg.hasUserSource(parsed.baseUrl, parsed.categoryId)) {
      return 'alreadyExists';
    }

    final api = _ref.read(piwigoApiProvider);
    final theme = await api.resolveCategory(parsed);
    if (theme == null) {
      if (await api.isApiBlocked(parsed.baseUrl)) return 'apiBlocked';
      return 'addFailed';
    }

    await cfg.addUserSource(PiwigoSource(
      baseUrl: parsed.baseUrl,
      rootCategoryId: parsed.categoryId,
      recursive: false,
      originalUrl: theme.originalUrl,
      cachedName: theme.nameRaw,
      cachedImageCount: theme.imageCount,
      cachedThumbnailUrl: theme.thumbnailUrl,
    ));

    _ref.read(themesProvider.notifier).addTheme(theme);

    final cache = _ref.read(cacheServiceProvider);
    // User-added themes always recurse into sub-albums (see getThemeImages).
    final images = await api.getThemeImages(
      theme.id,
      baseUrl: theme.sourceBaseUrl,
      recursive: true,
    );
    if (images.isNotEmpty) {
      cache.updateThemeImages(theme.displayName, images);
    }

    _syncRotationThemeNames();
    return null;
  }

  /// Creates a theme following a whole folder: everything inside belongs to
  /// it, now and later.
  ///
  /// Returns null on success, or a localizable error key.
  Future<String?> addFolderTheme(String root) async {
    if (root.trim().isEmpty) return 'invalidUrl';

    final cfg = _ref.read(themesConfigServiceProvider);
    if (cfg.hasLocalFolder(root)) return 'alreadyExists';

    return _createLocalTheme(LocalSource(
      id: _newLocalId(),
      kind: LocalThemeKind.folder,
      name: LocalSource.folderDisplayName(root),
      roots: [root],
    ));
  }

  /// Creates a theme from photos the user hand-picked inside [root].
  Future<String?> addCustomTheme({
    required String name,
    required String root,
    required List<String> items,
  }) async {
    if (items.isEmpty) return 'addFailed';

    return _createLocalTheme(LocalSource(
      id: _newLocalId(),
      kind: LocalThemeKind.custom,
      name: name.trim().isEmpty ? LocalSource.folderDisplayName(root) : name.trim(),
      roots: [root],
      items: items,
    ));
  }

  Future<String?> _createLocalTheme(LocalSource source) async {
    final localSvc = _ref.read(localGalleryServiceProvider);

    final ThemeCategory theme;
    try {
      theme = await localSvc.resolveCategory(source);
    } catch (_) {
      return 'addFailed';
    }
    if (theme.imageCount == 0) return 'addFailed';

    await _ref.read(themesConfigServiceProvider).addLocalSource(source);
    _ref.read(themesProvider.notifier).addTheme(theme);
    await _refreshLocalTheme(source, theme);
    return null;
  }

  /// Renames a local theme, moving the rotation settings with it.
  Future<void> renameLocalTheme(LocalSource source, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == source.name) return;

    final previous = source.name;
    final updated = source.copyWith(name: trimmed);
    await _ref.read(themesConfigServiceProvider).updateLocalSource(updated);
    await _reloadLocalTheme(updated);

    // Slots pointing at the old name would silently stop rotating.
    final config = _ref.read(configProvider);
    if (config.screens.any((s) => s.themeNames.contains(previous))) {
      await _ref.read(configProvider.notifier).update((c) => c.copyWith(
            screens: c.screens
                .map((s) => s.themeNames.contains(previous)
                    ? s.copyWith(
                        themeNames: s.themeNames
                            .map((n) => n == previous ? trimmed : n)
                            .toList())
                    : s)
                .toList(),
          ));
    }
  }

  /// Adds photos to a custom theme, granting access to their folder if new.
  Future<void> addPhotosToTheme(
    LocalSource source, {
    required String root,
    required List<String> items,
  }) async {
    if (items.isEmpty) return;
    final merged = [...source.items];
    for (final item in items) {
      if (!merged.contains(item)) merged.add(item);
    }
    final roots = source.roots.contains(root)
        ? source.roots
        : [...source.roots, root];

    final updated = source.copyWith(items: merged, roots: roots);
    await _ref.read(themesConfigServiceProvider).updateLocalSource(updated);
    await _reloadLocalTheme(updated);
  }

  /// Drops photos from a custom theme. Nothing is deleted from the device.
  Future<void> removePhotosFromTheme(
    LocalSource source,
    Set<String> references,
  ) async {
    if (references.isEmpty) return;
    final updated = source.copyWith(
      items: source.items.where((i) => !references.contains(i)).toList(),
    );
    await _ref.read(themesConfigServiceProvider).updateLocalSource(updated);
    await _reloadLocalTheme(updated);
  }

  /// Rebuilds the theme entry and its cached image list after a change.
  Future<void> _reloadLocalTheme(LocalSource source) async {
    final localSvc = _ref.read(localGalleryServiceProvider);
    final theme = await localSvc.resolveCategory(source);
    final notifier = _ref.read(themesProvider.notifier);
    notifier.replaceTheme(theme);
    await _refreshLocalTheme(source, theme);
  }

  Future<void> _refreshLocalTheme(
      LocalSource source, ThemeCategory theme) async {
    final localSvc = _ref.read(localGalleryServiceProvider);
    final cache = _ref.read(cacheServiceProvider);
    cache.replaceThemeImages(
        theme.displayName, await localSvc.getImages(source));
    _syncRotationThemeNames();
  }

  String _newLocalId() =>
      'l${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// Removes a user-added theme. Any screen configured to use it is
  /// reverted to "all themes" so rotation does not silently break.
  Future<void> removeUserTheme(ThemeCategory theme) async {
    if (!theme.isUserAdded) return;
    final cfg = _ref.read(themesConfigServiceProvider);
    final localId = LocalSource.idFromSourceBaseUrl(theme.sourceBaseUrl);
    if (localId != null) {
      // Hand the folder grant back so the app keeps only what it still uses.
      final source = cfg.localSourceById(localId);
      for (final root in source?.roots ?? const <String>[]) {
        if (MediaAccessChannel.isDocumentUri(root)) {
          await MediaAccessChannel.releaseFolder(root);
        }
      }
      await cfg.removeLocalSource(localId);
    } else {
      await cfg.removeUserSource(theme.sourceBaseUrl, theme.id);
    }
    _ref.read(themesProvider.notifier).removeTheme(theme);

    final removedName = theme.displayName;
    final config = _ref.read(configProvider);
    final hasReferences =
        config.screens.any((s) => s.themeNames.contains(removedName));
    if (hasReferences) {
      await _ref.read(configProvider.notifier).update((c) {
        final updated = c.screens.map((s) {
          if (s.themeNames.contains(removedName)) {
            return s.copyWith(
              themeNames:
                  s.themeNames.where((n) => n != removedName).toList(),
            );
          }
          return s;
        }).toList();
        return c.copyWith(screens: updated);
      });
    }

    _syncRotationThemeNames();
  }

  /// Refreshes the rotation service's [allThemeNames] cache so that
  /// rotation in "all themes" mode picks from every currently-known theme.
  void _syncRotationThemeNames() {
    final rotation = _ref.read(rotationServiceProvider);
    rotation.allThemeNames =
        _ref.read(themesProvider).map((t) => t.displayName).toList();
  }
}

/// Local source backing a theme, or null when it is not a local one.
///
/// A plain function rather than a family provider: keying a provider on a
/// [ThemeCategory] would create — and keep — one instance per rebuild.
LocalSource? localSourceFor(WidgetRef ref, ThemeCategory theme) {
  final id = LocalSource.idFromSourceBaseUrl(theme.sourceBaseUrl);
  if (id == null) return null;
  return ref.read(themesConfigServiceProvider).localSourceById(id);
}

// --- Excluded images ---

/// Adds and removes images from the "never show again" list.
///
/// The cache is the single place that filters them out, so every consumer —
/// in-app rotation, prefetch and the Android background slideshow — honours
/// the list without knowing about it.
final exclusionsProvider = Provider<ExclusionsManager>((ref) {
  return ExclusionsManager(ref);
});

class ExclusionsManager {
  final Ref _ref;
  ExclusionsManager(this._ref);

  /// Bans the image currently displayed on [screenId] and immediately puts
  /// another one in its place, so the user is not left looking at it.
  Future<bool> excludeCurrent(int screenId) async {
    final path = _ref.read(currentWallpapersProvider)[screenId];
    if (path == null) return false;

    final cache = _ref.read(cacheServiceProvider);
    final theme = cache.themeOfCachedFile(path);
    if (theme == null) return false;

    final filename = p.basename(path);
    final entry =
        ExcludedImage(theme: theme, filename: filename, localPath: path);

    final config = _ref.read(configProvider);
    if (config.excludedImages.any((e) => e.key == entry.key)) return false;

    await _ref.read(configProvider.notifier).update((c) => c.copyWith(
          excludedImages: [...c.excludedImages, entry],
        ));

    await _ref.read(rotationServiceProvider).rotateScreen(screenId);
    return true;
  }

  Future<void> restore(ExcludedImage image) async {
    await _ref.read(configProvider.notifier).update((c) => c.copyWith(
          excludedImages:
              c.excludedImages.where((e) => e.key != image.key).toList(),
        ));
  }

  Future<void> clear() async {
    await _ref
        .read(configProvider.notifier)
        .update((c) => c.copyWith(excludedImages: const []));
  }
}

// --- Theme images (per category) ---

final themeImagesProvider = StateNotifierProvider.family<ThemeImagesNotifier,
    List<WallpaperImage>, int>((ref, categoryId) {
  return ThemeImagesNotifier();
});

class ThemeImagesNotifier extends StateNotifier<List<WallpaperImage>> {
  ThemeImagesNotifier() : super([]);

  void setImages(List<WallpaperImage> images) => state = images;
}

// --- Screens ---

final screensProvider =
    StateNotifierProvider<ScreensNotifier, List<ScreenInfo>>((ref) {
  return ScreensNotifier();
});

class ScreensNotifier extends StateNotifier<List<ScreenInfo>> {
  ScreensNotifier() : super([]);

  Future<void> detectScreens() async {
    state = await WallpaperChannel.getScreens();
  }
}

// --- Rotation state ---

final rotationRunningProvider = StateProvider<bool>((ref) => false);
final rotationPausedProvider = StateProvider<bool>((ref) => false);

// --- Current wallpapers per screen ---

final currentWallpapersProvider = StateProvider<Map<int, String>>((ref) => {});

// --- Loading states ---

final isLoadingProvider = StateProvider<bool>((ref) => true);
final statusMessageProvider = StateProvider<String>((ref) => '');
