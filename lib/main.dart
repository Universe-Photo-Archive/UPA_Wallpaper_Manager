import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'models/app_config.dart';
import 'models/theme_category.dart';
import 'models/theme_source.dart';
import 'providers/app_providers.dart';
import 'models/wallpaper_image.dart';
import 'services/autostart_service.dart';
import 'services/background_rotation_service.dart';
import 'services/cache_service.dart';
import 'services/config_service.dart';
import 'services/log_service.dart';
import 'services/rotation_service.dart';
import 'services/system_tray_service.dart';
import 'services/themes_config_service.dart';
import 'platform/wallpaper_channel.dart';
import 'platform/lockscreen_channel.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// CLI flag passed by Windows auto-start (Run registry key) so the app boots
/// straight into the system tray instead of popping a window in the user's
/// face on every login.
const String _kMinimizedFlag = '--minimized';

// Keep subscription alive to prevent GC
// ignore: unused_element
late final ProviderSubscription<AppConfig> _configSubscription;

final _autostart = AutostartService();
final _backgroundRotation = BackgroundRotationService();

/// True when the slideshow should actually be running: not paused and at
/// least one screen with rotation enabled.
bool _rotationWanted(AppConfig config) =>
    !config.slideshowPaused &&
    config.screens.any((s) => s.rotationEnabled);

/// Mirrors the current rotation settings into the Android background job.
///
/// The job runs without Dart, so it gets the images already downloaded for
/// the theme configured on the (single) mobile screen.
Future<void> _syncBackgroundRotation(
  ProviderContainer container,
  AppConfig config,
) async {
  if (!Platform.isAndroid) return;

  final screen = config.screens.isEmpty ? null : config.screens.first;
  final cache = container.read(cacheServiceProvider);

  final themes = (screen == null || screen.themeName == 'all')
      ? container.read(themesProvider).map((t) => t.displayName).toList()
      : [screen.themeName];

  final images = <String>[];
  for (final theme in themes) {
    images.addAll(cache.getCachedPaths(theme));
  }

  await _backgroundRotation.sync(
    enabled: _rotationWanted(config),
    intervalMinutes: (screen?.rotationDelaySeconds ?? 900) ~/ 60,
    lockscreen: config.lockscreenEnabled,
    images: images,
    current: container.read(currentWallpapersProvider)[screen?.screenId ?? 0],
  );
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // When launched at OS startup we receive [--minimized] so the window can
  // boot hidden (only the tray icon remains visible).
  final startMinimized = args.contains(_kMinimizedFlag);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    // Keep WindowOptions minimal: any extra option (custom backgroundColor,
    // titleBarStyle, etc.) interferes with Win11's immersive dark-mode title
    // bar and ends up rendering the min/max/close icons in a near-invisible
    // color. The defaults give us a normal Windows title bar with all three
    // buttons.
    final windowOptions = WindowOptions(
      size: const Size(1100, 720),
      minimumSize: const Size(800, 500),
      center: true,
      title: 'UPA Wallpaper Manager',
      skipTaskbar: startMinimized,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) {
        // Stay hidden — the system tray icon will be the only visible UI.
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  final configService = ConfigService();
  await configService.init();

  final logService = LogService(debugMode: configService.config.debugMode);
  await logService.init();
  logService.info('=== UPA Wallpaper Manager starting ===');

  // Set up the OS auto-start integration. The package writes / removes the
  // appropriate registry entry whenever we call enable / disable. We do this
  // up-front (before [runApp]) so a fresh install also gets registered if
  // the user already had [launchOnStartup] = true from a previous version.
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      // launch_at_startup is still used on macOS / Linux, and on Windows to
      // clean up the legacy HKCU Run entry written by versions <= 1.x.
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
        // Pass --minimized so the next OS boot starts straight into tray.
        args: [_kMinimizedFlag],
        packageName: packageInfo.packageName,
      );
      final shouldEnable = configService.config.launchOnStartup;
      final actuallyEnabled = await _autostart.isEnabled();
      if (shouldEnable && !actuallyEnabled) {
        await _autostart.enable();
        _log.i('autostart: enabled');
      } else if (!shouldEnable && actuallyEnabled) {
        await _autostart.disable();
        _log.i('autostart: disabled');
      }
    } catch (e) {
      _log.w('autostart setup failed: $e');
    }
  }

  final cacheService = CacheService(
    maxCachedImages: 100,
    prefetchCount: 10,
  );
  await cacheService.init();

  final themesConfigService = ThemesConfigService();
  await themesConfigService.init();

  final rotationService = RotationService(
    cache: cacheService,
    randomMode: configService.config.randomMode,
  );

  final trayService = SystemTrayService();

  // Probe lock-screen capability once (admin + Windows edition). The result
  // is cached in [lockscreenSupportProvider] for the UI; we keep a local copy
  // here so the rotation callback can short-circuit on unsupported systems
  // without async work on every wallpaper change.
  bool lockscreenSupported = false;
  if (Platform.isWindows) {
    try {
      lockscreenSupported = await LockscreenChannel.isLockscreenSupported();
      _log.i('Lockscreen support: $lockscreenSupported');
    } catch (e) {
      _log.w('Failed to probe lockscreen support: $e');
    }
  } else if (Platform.isAndroid) {
    try {
      // Supported since Android 7.0 (FLAG_LOCK) — no admin requirement.
      lockscreenSupported = await LockscreenChannel.isSupported();
      _log.i('Lockscreen support (Android): $lockscreenSupported');
    } catch (e) {
      _log.w('Failed to probe lockscreen support: $e');
    }
  }

  final container = ProviderContainer(overrides: [
    configServiceProvider.overrideWithValue(configService),
    cacheServiceProvider.overrideWithValue(cacheService),
    logServiceProvider.overrideWithValue(logService),
    rotationServiceProvider.overrideWithValue(rotationService),
    themesConfigServiceProvider.overrideWithValue(themesConfigService),
  ]);

  // Rotation callback: always update preview, then try to set native wallpaper
  rotationService.onRotation = (screenId, imagePath) async {
    _log.d('onRotation: screen=$screenId path=$imagePath');

    // Resolve which theme this image belongs to (best-effort).
    final themeName = rotationService.currentThemes[screenId] ??
        rotationService.themeNameForScreen(screenId) ??
        'unknown';

    logService.logWallpaperChange(
      screenId: screenId,
      themeName: themeName,
      imagePath: imagePath,
    );

    // Always update preview regardless of platform success
    final current =
        Map<int, String>.from(container.read(currentWallpapersProvider));
    current[screenId] = imagePath;
    container.read(currentWallpapersProvider.notifier).state = current;

    try {
      final success = await WallpaperChannel.setWallpaper(
        imagePath: imagePath,
        screenId: screenId,
      );
      _log.d('setWallpaper result: $success');
      logService.debug(
          'Native setWallpaper(screen=$screenId) -> $success');

      if (success &&
          configService.config.lockscreenEnabled &&
          screenId == 0 &&
          lockscreenSupported) {
        final ok = await LockscreenChannel.setLockscreen(imagePath);
        logService.debug(
            'Lockscreen update for $imagePath -> ${ok ? "OK" : "FAILED"}');
      }
    } catch (e) {
      _log.e('setWallpaper error: $e');
      logService.error('setWallpaper failed for screen $screenId', e);
    }
  };

  // Listen to config changes and sync RotationService in real-time
  // Store the subscription to prevent garbage collection
  _configSubscription =
      container.listen<AppConfig>(configProvider, (prev, next) {
    _log.d('Config changed, syncing RotationService...');

    logService.debugMode = next.debugMode;
    rotationService.randomMode = next.randomMode;

    // Sync auto-start with the OS whenever the user toggles the setting.
    if (prev?.launchOnStartup != next.launchOnStartup) {
      _syncLaunchOnStartup(next.launchOnStartup);
    }

    var delayOrEnabledChanged = false;
    for (final sc in next.screens) {
      final prevSc = prev?.screens
          .where((p) => p.screenId == sc.screenId)
          .firstOrNull;

      rotationService.setScreenConfig(ScreenRotationConfig(
        screenId: sc.screenId,
        themeName: sc.themeName,
        enabled: sc.rotationEnabled,
        delaySeconds: sc.rotationDelaySeconds,
      ));

      // If theme changed for this screen, force immediate rotation
      if (prevSc != null && prevSc.themeName != sc.themeName) {
        _log.i(
            'Theme changed on screen ${sc.screenId}: ${prevSc.themeName} -> ${sc.themeName}');
        rotationService.rotateScreen(sc.screenId);
      }

      if (prevSc != null &&
          (prevSc.rotationDelaySeconds != sc.rotationDelaySeconds ||
              prevSc.rotationEnabled != sc.rotationEnabled)) {
        delayOrEnabledChanged = true;
      }
    }

    // Restart timers only when delay / enabled actually changed — not on
    // every unrelated config write (language, cache size, ...).
    if (delayOrEnabledChanged &&
        rotationService.isRunning &&
        !rotationService.isPaused) {
      rotationService.restartTimers();
    }

    // Keep the Android background job in sync with the rotation settings.
    if (Platform.isAndroid) {
      _syncBackgroundRotation(container, next);
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const UpaWallpaperApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeApp(container, rotationService, trayService);
  });
}

Future<void> _initializeApp(
  ProviderContainer container,
  RotationService rotationService,
  SystemTrayService trayService,
) async {
  try {
    _log.i('Starting initialization...');

    await container.read(screensProvider.notifier).detectScreens();
    final screens = container.read(screensProvider);
    _log.i('Detected ${screens.length} screen(s)');

    // Existing configs may carry a delay shorter than what the Android
    // background job supports (seconds, or a handful of minutes). Raise them
    // once, otherwise the rotation would silently stop when the app closes.
    if (Platform.isAndroid) {
      final current = container.read(configProvider);
      final needsMigration = current.screens.any((s) =>
          s.rotationDelayUnit == 'seconds' ||
          (s.rotationDelayUnit == 'minutes' &&
              s.rotationDelay < WallpaperChannel.minBackgroundIntervalMinutes));
      if (needsMigration) {
        await container.read(configProvider.notifier).update((c) {
          final screens = c.screens
              .map((s) => (s.rotationDelayUnit == 'hours')
                  ? s
                  : s.copyWith(
                      rotationDelayUnit: 'minutes',
                      rotationDelay: s.rotationDelayUnit == 'minutes' &&
                              s.rotationDelay >=
                                  WallpaperChannel.minBackgroundIntervalMinutes
                          ? s.rotationDelay
                          : WallpaperChannel.minBackgroundIntervalMinutes,
                    ))
              .toList();
          return c.copyWith(screens: screens);
        });
        _log.i('Android: rotation delays raised to the 15-minute minimum');
      }
    }

    // Ensure config has entries for all detected screens
    final config = container.read(configProvider);
    if (config.screens.length < screens.length) {
      final updatedScreens = List<ScreenConfig>.from(config.screens);
      for (int i = updatedScreens.length; i < screens.length; i++) {
        updatedScreens.add(ScreenConfig(screenId: i));
      }
      await container
          .read(configProvider.notifier)
          .update((c) => c.copyWith(screens: updatedScreens));
    }

    // Seed the preview map with each screen's *current* OS wallpaper so that
    // screens with rotation disabled (which never get a callback from the
    // rotation service) still display the wallpaper actually shown on the
    // desktop. Rotation will overwrite these entries on enabled screens.
    final initialWallpapers = <int, String>{};
    final cacheForPinning = container.read(cacheServiceProvider);

    // Android cannot report the current wallpaper path, but the background job
    // records what it applied — use it so the preview matches the desktop.
    if (Platform.isAndroid) {
      final applied = await _backgroundRotation.lastAppliedWallpaper();
      if (applied != null) {
        initialWallpapers[0] = applied;
        cacheForPinning.pinWallpaper(0, applied);
      }
    }

    for (final s in screens) {
      final path = await WallpaperChannel.getWallpaper(screenId: s.id);
      if (path != null) {
        initialWallpapers[s.id] = path;
        // The OS wallpaper may be a file from our cache (set during a
        // previous session) — protect it from cleanup so the preview and
        // the desktop keep a valid file until the next rotation.
        cacheForPinning.pinWallpaper(s.id, path);
      }
    }
    if (initialWallpapers.isNotEmpty) {
      container.read(currentWallpapersProvider.notifier).state =
          initialWallpapers;
      _log.i('Seeded preview with ${initialWallpapers.length} OS wallpaper(s)');
    }

    // System tray
    if (SystemTrayService.isDesktop) {
      trayService.onShow = () => trayService.showWindow();
      trayService.onQuit = () => exit(0);
      trayService.onRotateNow = () => rotationService.rotateNow();
      trayService.onTogglePause = () {
        final paused = rotationService.togglePause();
        container.read(rotationPausedProvider.notifier).state = paused;
        trayService.updatePauseState(paused);
        // Persist so the toggle survives app restarts.
        container
            .read(configProvider.notifier)
            .update((c) => c.copyWith(slideshowPaused: paused));
      };
      await trayService.init();
      _log.i('System tray initialized');
    }

    // Refresh default themes config from GitHub (best-effort, non-blocking
    // failures fall back to the previous on-disk / bundled copy).
    final themesConfigService = container.read(themesConfigServiceProvider);
    container.read(statusMessageProvider.notifier).state =
        'Vérification de la liste des thèmes...';
    await themesConfigService.refreshDefaultConfigFromGitHub();

    // Connect to Piwigo (default UPA gallery for the connectivity check)
    container.read(statusMessageProvider.notifier).state =
        'Connexion à Piwigo...';
    final api = container.read(piwigoApiProvider);

    _log.i('Testing Piwigo connection...');
    final isOnline = await api.testConnection();
    container.read(isOnlineProvider.notifier).state = isOnline;
    _log.i('Piwigo connection: ${isOnline ? "OK" : "FAILED"}');

    final allThemes = <ThemeCategory>[];

    final localGallery = container.read(localGalleryServiceProvider);

    if (isOnline) {
      container.read(statusMessageProvider.notifier).state =
          'Chargement des thèmes...';

      // Load themes from every default source
      for (final src in themesConfigService.defaultPiwigoSources) {
        final themes = await api.getThemesFromSource(src, isUserAdded: false);
        allThemes.addAll(themes);
      }

      // Load user-added Piwigo themes (each source = one theme)
      for (final src in themesConfigService.userPiwigoSources) {
        final themes = await api.getThemesFromSource(src, isUserAdded: true);
        if (themes.isNotEmpty) {
          allThemes.addAll(themes);
        } else if (src.cachedName != null) {
          // Offline / unreachable: build a placeholder theme from cached meta.
          allThemes.add(ThemeCategory(
            id: src.rootCategoryId,
            name: src.cachedName!,
            nameRaw: src.cachedName!,
            url: src.originalUrl ?? '',
            imageCount: src.cachedImageCount ?? 0,
            thumbnailUrl: src.cachedThumbnailUrl,
            sourceBaseUrl: src.baseUrl,
            isUserAdded: true,
            originalUrl: src.originalUrl,
          ));
        }
      }
    }

    // Local themes are always loaded (no network needed).
    for (final src in themesConfigService.userLocalSources) {
      try {
        final theme = await localGallery.resolveCategory(src);
        allThemes.add(theme);
      } catch (e) {
        _log.w('Failed to resolve local theme ${src.folderPath}: $e');
      }
    }

    _log.i('Loaded ${allThemes.length} theme(s) total');
    container.read(themesProvider.notifier).setThemes(allThemes);

    rotationService.allThemeNames =
        allThemes.map((t) => t.displayName).toList();

    if (allThemes.isNotEmpty) {
      final cache = container.read(cacheServiceProvider);
      for (final theme in allThemes) {
        container.read(statusMessageProvider.notifier).state =
            'Chargement: ${theme.displayName}...';

        final List<WallpaperImage> images;
        if (theme.sourceBaseUrl.startsWith(LocalSource.urlScheme)) {
          final folderPath =
              theme.sourceBaseUrl.substring(LocalSource.urlScheme.length);
          images = await localGallery.getImages(LocalSource(
            folderPath: folderPath,
            name: theme.nameRaw,
            id: theme.id,
            recursive: true,
          ));
        } else if (isOnline) {
          // Recurse into sub-albums whenever the category's photos live in
          // its children (e.g. "Thomas Pesquet" has 0 direct images but
          // 2138 in Mission Alpha / Mission Proxima) and for all user-added
          // themes. Leaf categories stay flat to avoid double-counting.
          images = await api.getThemeImages(
            theme.id,
            baseUrl: theme.sourceBaseUrl,
            recursive: theme.needsRecursiveFetch,
          );
        } else {
          images = const [];
        }

        _log.i('  ${theme.displayName}: ${images.length} images');
        cache.updateThemeImages(theme.displayName, images);

        // Local images are already on-disk; no need to pre-download.
        if (!theme.sourceBaseUrl.startsWith(LocalSource.urlScheme) && isOnline) {
          final cached = cache.getCachedPaths(theme.displayName).length;
          if (cached < 5) {
            final dl = await cache.downloadBatch(theme.displayName, count: 5);
            _log.i('  Downloaded $dl new images for ${theme.displayName}');
          }
        }
      }
    }

    if (!isOnline) {
      // Offline: also populate Piwigo user themes from cached metadata so
      // the dropdown is not completely empty (alongside local themes).
      for (final src in themesConfigService.userPiwigoSources) {
        if (src.cachedName == null) continue;
        if (allThemes.any((t) =>
            t.sourceBaseUrl == src.baseUrl && t.id == src.rootCategoryId)) {
          continue;
        }
        allThemes.add(ThemeCategory(
          id: src.rootCategoryId,
          name: src.cachedName!,
          nameRaw: src.cachedName!,
          url: src.originalUrl ?? '',
          imageCount: src.cachedImageCount ?? 0,
          thumbnailUrl: src.cachedThumbnailUrl,
          sourceBaseUrl: src.baseUrl,
          isUserAdded: true,
          originalUrl: src.originalUrl,
        ));
      }
      container.read(themesProvider.notifier).setThemes(allThemes);
      rotationService.allThemeNames =
          allThemes.map((t) => t.displayName).toList();
      container.read(statusMessageProvider.notifier).state =
          'Impossible de se connecter à Piwigo';
    } else {
      container.read(statusMessageProvider.notifier).state = '';
    }

    // Configure rotation for each screen
    final finalConfig = container.read(configProvider);
    for (final sc in finalConfig.screens) {
      rotationService.setScreenConfig(ScreenRotationConfig(
        screenId: sc.screenId,
        themeName: sc.themeName,
        enabled: sc.rotationEnabled,
        delaySeconds: sc.rotationDelaySeconds,
      ));
    }

    rotationService.start();
    container.read(rotationRunningProvider.notifier).state = true;

    // Force initial rotation
    _log.i('Performing initial rotation...');
    await rotationService.rotateNow();
    _log.i('Initial rotation done');

    if (Platform.isAndroid) {
      await _syncBackgroundRotation(container, container.read(configProvider));
    }

    // Restore the slideshow pause state persisted in the config so the user's
    // last choice (paused / running) carries across restarts.
    if (finalConfig.slideshowPaused && !rotationService.isPaused) {
      rotationService.pause();
      container.read(rotationPausedProvider.notifier).state = true;
      if (SystemTrayService.isDesktop) {
        trayService.updatePauseState(true);
      }
      _log.i('Restored slideshow paused state from config');
    }

    container.read(isLoadingProvider.notifier).state = false;
    _log.i('Initialization complete');
  } catch (e, stack) {
    _log.e('Initialization error: $e\n$stack');
    container.read(statusMessageProvider.notifier).state = 'Erreur: $e';
    container.read(isLoadingProvider.notifier).state = false;
  }
}

/// Reflects [enabled] on the OS auto-start mechanism (Scheduled Task on
/// Windows so the elevated app starts at logon, LaunchAgent on macOS,
/// .desktop on Linux). Failures are logged but never thrown — the user can
/// always retry by toggling the setting.
Future<void> _syncLaunchOnStartup(bool enabled) async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  try {
    final actuallyEnabled = await _autostart.isEnabled();
    if (enabled && !actuallyEnabled) {
      await _autostart.enable();
      _log.i('autostart: enabled');
    } else if (!enabled && actuallyEnabled) {
      await _autostart.disable();
      _log.i('autostart: disabled');
    }
  } catch (e) {
    _log.w('autostart sync failed: $e');
  }
}
