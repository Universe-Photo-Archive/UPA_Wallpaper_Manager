import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/shell_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/gallery_screen.dart';
import 'ui/screens/settings_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => ShellScreen(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeScreen()),
        ),
        GoRoute(
          path: '/gallery',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: GalleryScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
      ],
    ),
  ],
);

class UpaWallpaperApp extends ConsumerWidget {
  const UpaWallpaperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);

    final themeMode = switch (config.uiThemeMode) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

    final locale = Locale(config.language);

    // Icons carry no textScaler, so the scale is pushed through the theme as
    // well; widgets that hard-code a size keep it, which is intended for the
    // small decorations.
    final scale = config.uiScale;
    ThemeData scaled(ThemeData base) => base.copyWith(
          iconTheme: base.iconTheme.copyWith(size: 24 * scale),
        );

    return MaterialApp.router(
      title: 'UPA Wallpaper Manager',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: scale,
              maxScaleFactor: scale,
            ),
          ),
          child: child!,
        );
      },
      theme: scaled(AppTheme.lightTheme),
      darkTheme: scaled(AppTheme.darkTheme),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}
