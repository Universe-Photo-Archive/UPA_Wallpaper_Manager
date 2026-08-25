import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'models/app_config.dart';
import 'models/theme_category.dart';
import 'models/theme_source.dart';
import 'providers/app_providers.dart';
import 'models/wallpaper_image.dart';
import 'services/autostart_service.dart';
import 'l10n/app_localizations.dart';
import 'services/background_rotation_service.dart'
    show BackgroundRotationService, QuietHoursState, RotationTargetState;
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
Timer? _backgroundStateRefresh;
bool _toppingUp = false;

/// How many unseen images each rotating theme should keep ready on disk.
const int _minUnseenPerTheme = 25;

/// Deletes the photo copies made by the versions that could not read the
/// user's folders in place.
Future<void> _discardLegacyPhotoCopies() async {
  try {
    final support = await getApplicationSupportDirectory();
    final legacy = Directory('${support.path}/local_themes');
    if (await legacy.exists()) {
      await legacy.delete(recursive: true);
      _log.i('Removed legacy imported photo copies');
    }
  } catch (e) {
    _log.w('Could not remove legacy photo copies: $e');
  }
}

/// Reflects a wallpaper applied outside of Dart (Android slideshow service)
/// in the app state, so the preview matches the device.
void _applyExternalWallpaper(
    ProviderContainer container, int screenId, String path) {
  if (!File(path).existsSync()) return;
  final current = Map<int, String>.from(
      container.read(currentWallpapersProvider));
  if (current[screenId] == path) return;
  current[screenId] = path;
  container.read(currentWallpapersProvider.notifier).state = current;
  container.read(cacheServiceProvider).pinWallpaper(screenId, path);
  _log.d('Preview synced with background rotation: screen=$screenId $path');
}

/// Re-reads what the background rotation did whenever the app is shown again.
class _ForegroundWallpaperSync with WidgetsBindingObserver {
  final ProviderContainer container;
  _ForegroundWallpaperSync(this.container);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _backgroundRotation.lastAppliedWallpapers().then((applied) {
      applied.forEach((screenId, path) {
        _applyExternalWallpaper(container, screenId, path);
      });
    });
    // The notification's stop button may have been used while away.
    _backgroundRotation.allTargetsDisabled().then((stopped) {
      if (!stopped) return;
      if (!container.read(configProvider).screens.any((s) => s.rotationEnabled)) {
        return;
      }
      _stopAllSlideshows(container);
    });
    // Hand the service a fresh image list: cache cleanup may have removed
    // some of the files it knows about, and new ones have been downloaded.
    _topUpRotationCache(container, container.read(configProvider)).then(
      (_) => _syncBackgroundRotation(container, container.read(configProvider)),
    );
  }
}

/// Switches every slideshow off, as the notification's stop button does.
void _stopAllSlideshows(ProviderContainer container) {
  final config = container.read(configProvider);
  if (!config.screens.any((s) => s.rotationEnabled)) return;
  container.read(configProvider.notifier).update((c) => c.copyWith(
        slideshowPaused: false,
        screens:
            c.screens.map((s) => s.copyWith(rotationEnabled: false)).toList(),
      ));
  _log.i('Slideshows stopped from the notification');
}

/// Downloads more images of the themes in rotation while the app is open.
///
/// The background slideshow only draws from what is already on disk, so a
/// large theme would otherwise cycle through the handful fetched at startup.
/// Topping up here is what lets it eventually go through everything.
Future<void> _topUpRotationCache(
  ProviderContainer container,
  AppConfig config,
) async {
  if (_toppingUp || !container.read(isOnlineProvider)) return;
  _toppingUp = true;
  try {
    final cache = container.read(cacheServiceProvider);
    final allThemes =
        container.read(themesProvider).map((t) => t.displayName).toList();

    final active = <String>{};
    for (final screen in config.screens) {
      if (!screen.rotationEnabled) continue;
      active.addAll(screen.resolveThemes(allThemes));
    }

    for (final theme in active) {
      // Local themes are already on the device; nothing to fetch.
      if (cache.getThemeImages(theme).isEmpty) continue;
      if (cache.countReadyUndisplayed(theme) >= _minUnseenPerTheme) continue;
      final downloaded = await cache.downloadBatch(theme, count: 10);
      if (downloaded > 0) {
        _log.i('Topped up "$theme" with $downloaded image(s)');
      }
    }
  } catch (e) {
    _log.w('Cache top-up failed: $e');
  } finally {
    _toppingUp = false;
  }
}

/// Mirrors the current rotation settings into the Android slideshow service.
///
/// The service runs without Dart, so each target is handed the images already
/// downloaded for its own theme.
Future<void> _syncBackgroundRotation(
  ProviderContainer container,
  AppConfig config,
) async {
  if (!Platform.isAndroid) return;

  final cache = container.read(cacheServiceProvider);
  final allThemes =
      container.read(themesProvider).map((t) => t.displayName).toList();
  final wallpapers = container.read(currentWallpapersProvider);

  // Take note of what rotated while the app was away, so the cycle and the
  // cache cleanup stay in step with what the user really saw.
  cache.markDisplayedReferences(await _backgroundRotation.shownReferences());

  final targets = <RotationTargetState>[];
  for (final screen in config.screens) {
    final themes = screen.resolveThemes(allThemes);
    final images = <String>[];
    for (final theme in themes) {
      images.addAll(cache.getCachedPaths(theme));
    }
    targets.add(RotationTargetState(
      id: screen.screenId,
      enabled: screen.rotationEnabled,
      intervalSeconds: screen.rotationDelaySeconds,
      // Empty tells the notification to say "all themes"; a single name is
      // shown as is, several are joined.
      theme: screen.usesAllThemes ? '' : screen.themeNames.join(', '),
      images: images,
      current: wallpapers[screen.screenId],
    ));
  }

  await _backgroundRotation.sync(
    paused: config.slideshowPaused,
    targets: targets,
    quietHours: QuietHoursState(
      enabled: config.quietHours.enabled && config.quietHours.isValid,
      startMinutes: config.quietHours.startMinutes,
      endMinutes: config.quietHours.endMinutes,
    ),
    // The notification must follow the language chosen in the app, which is
    // not necessarily the device's, so the translations travel with the state.
    labels: _notificationLabels(config.language),
  );
}

/// Notification texts in the app's language, handed to the native service.
Map<String, String> _notificationLabels(String languageCode) {
  final l10n = lookupAppLocalizations(Locale(languageCode));
  return {
    'home': l10n.galleryTargetWallpaper,
    'lock': l10n.galleryTargetLockscreen,
    'allThemes': l10n.screenAllThemes,
    'idle': l10n.notificationIdle,
    'quiet': l10n.notificationQuiet,
    'stop': l10n.notificationStop,
    'next': l10n.notificationNext,
  };
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
    // A wide pool is what keeps the background rotation varied: it can only
    // draw from what is already on disk, since it never touches the network.
    maxCachedImages: 300,
    prefetchCount: 10,
  );
  await cacheService.init();
  cacheService.excludedKeys =
      configService.config.excludedImages.map((e) => e.key).toSet();

  final themesConfigService = ThemesConfigService();
  await themesConfigService.init();

  // Earlier versions copied the user's photos into the app; those themes are
  // gone and the copies are dead weight.
  unawaited(_discardLegacyPhotoCopies());

  final rotationService = RotationService(
    cache: cacheService,
    randomMode: configService.config.randomMode,
  );
  // Quiet hours are enforced natively on Android; this covers the desktop
  // timers, which Dart drives itself.
  rotationService.shouldRotateNow = () {
    final now = DateTime.now();
    return !configService.config.quietHours
        .containsMinutes(now.hour * 60 + now.minute);
  };

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

    // Let the Android slideshow service know what is already on screen so it
    // does not pick the same image on its next tick.
    if (Platform.isAndroid) {
      _backgroundRotation.updateCurrent(screenId, imagePath);
    }

    try {
      // On Android screen 1 *is* the lock screen, and the native side maps it
      // to FLAG_LOCK — no separate lock-screen call is needed there.
      final success = await WallpaperChannel.setWallpaper(
        imagePath: imagePath,
        screenId: screenId,
      );
      _log.d('setWallpaper result: $success');
      logService.debug(
          'Native setWallpaper(screen=$screenId) -> $success');

      if (success &&
          !Platform.isAndroid &&
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
    cacheService.excludedKeys =
        next.excludedImages.map((e) => e.key).toSet();

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
        themeNames: sc.themeNames,
        enabled: sc.rotationEnabled,
        delaySeconds: sc.rotationDelaySeconds,
      ));

      // If the theme selection changed for this screen, rotate now.
      final prevThemes = prevSc?.themeNames.join('|');
      if (prevSc != null && prevThemes != sc.themeNames.join('|')) {
        _log.i('Themes changed on screen ${sc.screenId}: '
            '$prevThemes -> ${sc.themeNames.join("|")}');
        rotationService.rotateScreen(sc.screenId);
      }

      // Turning a slideshow on shows a new image straight away, instead of
      // leaving the user waiting for the first tick.
      if (prevSc != null && !prevSc.rotationEnabled && sc.rotationEnabled) {
        rotationService.rotateScreen(sc.screenId);
      }

      if (prevSc != null &&
          (prevSc.rotationDelaySeconds != sc.rotationDelaySeconds ||
              prevSc.rotationEnabled != sc.rotationEnabled)) {
        delayOrEnabledChanged = true;
      }
    }

    // Restart timers only when delay / enabled actually changed — not on
    // every unrelated config write (language, cache size, ...). On Android
    // the native service owns the periodic rotation, so Dart has no timers.
    if (!Platform.isAndroid &&
        delayOrEnabledChanged &&
        rotationService.isRunning &&
        !rotationService.isPaused) {
      rotationService.restartTimers();
    }

    // Keep the Android background job in sync with the rotation settings.
    if (Platform.isAndroid) {
      _syncBackgroundRotation(container, next);
    }
  });

  if (Platform.isAndroid) {
    // The slideshow service applies wallpapers natively; mirror them into the
    // preview so the app never shows something other than the real wallpaper,
    // and follow the pause button of its notification.
    WallpaperChannel.listenToNativeRotation(
      onWallpaperChanged: (screenId, path) =>
          _applyExternalWallpaper(container, screenId, path),
      onSlideshowStopped: () => _stopAllSlideshows(container),
    );
    // Also re-read the state file when the app comes back to the foreground,
    // covering rotations that happened while it was closed.
    WidgetsBinding.instance.addObserver(
      _ForegroundWallpaperSync(container),
    );
  }

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

    // Mobile has no pause any more: the notification stops the slideshow by
    // switching the slots off. Clear a flag left over by an older build,
    // which would otherwise keep the service from ever starting again.
    if (Platform.isAndroid && container.read(configProvider).slideshowPaused) {
      await container
          .read(configProvider.notifier)
          .update((c) => c.copyWith(slideshowPaused: false));
    }

    // Seconds are not offered on mobile; the slideshow service works in
    // minutes. Older configs written before that are converted once.
    if (Platform.isAndroid) {
      final current = container.read(configProvider);
      if (current.screens.any((s) => s.rotationDelayUnit == 'seconds')) {
        await container.read(configProvider.notifier).update((c) {
          final screens = c.screens
              .map((s) => s.rotationDelayUnit == 'seconds'
                  ? s.copyWith(
                      rotationDelayUnit: 'minutes',
                      rotationDelay:
                          s.rotationDelay < 60 ? 1 : s.rotationDelay ~/ 60,
                    )
                  : s)
              .toList();
          return c.copyWith(screens: screens);
        });
        _log.i('Android: second-based delays converted to minutes');
      }
    }

    // Ensure config has entries for all detected screens. On Android the
    // second "screen" is the lock screen, which starts disabled so nothing
    // changes for users who only want the home wallpaper to rotate.
    final config = container.read(configProvider);
    if (config.screens.length < screens.length) {
      final updatedScreens = List<ScreenConfig>.from(config.screens);
      for (int i = updatedScreens.length; i < screens.length; i++) {
        updatedScreens.add(ScreenConfig(
          screenId: i,
          rotationEnabled: !(Platform.isAndroid && i == 1),
        ));
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

    // Android cannot report the current wallpaper path, but the slideshow
    // service records what it applied — use it so the previews match.
    if (Platform.isAndroid) {
      final applied = await _backgroundRotation.lastAppliedWallpapers();
      applied.forEach((screenId, path) {
        initialWallpapers[screenId] = path;
        cacheForPinning.pinWallpaper(screenId, path);
      });
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
        _log.w('Failed to resolve local theme ${src.name}: $e');
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
        final localId = LocalSource.idFromSourceBaseUrl(theme.sourceBaseUrl);
        final localSource = localId == null
            ? null
            : themesConfigService.localSourceById(localId);
        if (localSource != null) {
          images = await localGallery.getImages(localSource);
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
        themeNames: sc.themeNames,
        enabled: sc.rotationEnabled,
        delaySeconds: sc.rotationDelaySeconds,
      ));
    }

    // On Android the periodic rotation belongs to the native slideshow
    // service, which keeps its schedule when the app is closed. Starting the
    // Dart timers as well would rotate twice.
    if (!Platform.isAndroid) {
      rotationService.start();
      container.read(rotationRunningProvider.notifier).state = true;

      // Force initial rotation
      _log.i('Performing initial rotation...');
      await rotationService.rotateNow();
      _log.i('Initial rotation done');
    } else {
      container.read(rotationRunningProvider.notifier).state = true;
      // Give each enabled slot an image right away if it has none yet.
      final wallpapers = container.read(currentWallpapersProvider);
      for (final sc in finalConfig.screens) {
        if (sc.rotationEnabled && wallpapers[sc.screenId] == null) {
          await rotationService.rotateScreen(sc.screenId);
        }
      }
    }

    if (Platform.isAndroid) {
      // The image list handed to the service goes stale as the cache evolves:
      // cleanup deletes old files and prefetch adds new ones. Refreshing it
      // regularly is what keeps the background rotation alive over days.
      _backgroundStateRefresh?.cancel();
      _backgroundStateRefresh = Timer.periodic(
        const Duration(minutes: 10),
        (_) async {
          await _topUpRotationCache(container, container.read(configProvider));
          await _syncBackgroundRotation(
              container, container.read(configProvider));
        },
      );
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
