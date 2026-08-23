class ScreenConfig {
  final int screenId;

  /// Themes this slot picks from. Empty means "every theme", which is also
  /// what the user sees when they tick the master checkbox.
  List<String> themeNames;

  bool rotationEnabled;
  int rotationDelay;
  String rotationDelayUnit; // 'seconds', 'minutes', 'hours'
  String? currentWallpaperPath;

  ScreenConfig({
    required this.screenId,
    this.themeNames = const [],
    this.rotationEnabled = true,
    this.rotationDelay = 15,
    this.rotationDelayUnit = 'minutes',
    this.currentWallpaperPath,
  });

  bool get usesAllThemes => themeNames.isEmpty;

  /// Themes to draw from, [allThemes] standing in for "every theme".
  List<String> resolveThemes(List<String> allThemes) =>
      usesAllThemes ? allThemes : themeNames;

  int get rotationDelaySeconds {
    switch (rotationDelayUnit) {
      case 'minutes':
        return rotationDelay * 60;
      case 'hours':
        return rotationDelay * 3600;
      default:
        return rotationDelay;
    }
  }

  factory ScreenConfig.fromJson(Map<String, dynamic> json) {
    // Configs written before multi-selection carried a single themeName,
    // with the literal 'all' standing for every theme.
    final legacy = json['themeName'] as String?;
    final names = (json['themeNames'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        ((legacy == null || legacy == 'all') ? const <String>[] : [legacy]);

    return ScreenConfig(
      screenId: json['screenId'] as int,
      themeNames: names,
      rotationEnabled: json['rotationEnabled'] as bool? ?? true,
      rotationDelay: json['rotationDelay'] as int? ?? 15,
      rotationDelayUnit: json['rotationDelayUnit'] as String? ?? 'minutes',
      currentWallpaperPath: json['currentWallpaperPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'screenId': screenId,
        'themeNames': themeNames,
        'rotationEnabled': rotationEnabled,
        'rotationDelay': rotationDelay,
        'rotationDelayUnit': rotationDelayUnit,
        'currentWallpaperPath': currentWallpaperPath,
      };

  /// Immutable-style update. Callers must NOT mutate a [ScreenConfig] that
  /// is already part of the app state: the previous and next configs would
  /// then share the same instance and change-detection (e.g. "theme changed
  /// on screen X -> rotate now") would silently stop working.
  ScreenConfig copyWith({
    List<String>? themeNames,
    bool? rotationEnabled,
    int? rotationDelay,
    String? rotationDelayUnit,
    String? currentWallpaperPath,
  }) {
    return ScreenConfig(
      screenId: screenId,
      themeNames: themeNames ?? this.themeNames,
      rotationEnabled: rotationEnabled ?? this.rotationEnabled,
      rotationDelay: rotationDelay ?? this.rotationDelay,
      rotationDelayUnit: rotationDelayUnit ?? this.rotationDelayUnit,
      currentWallpaperPath: currentWallpaperPath ?? this.currentWallpaperPath,
    );
  }
}


/// An image the user never wants to see again, on any slot.
///
/// Identified by theme + file name rather than by absolute path: the file is
/// re-downloaded to the same place after a cache clear, and the pair stays
/// stable across reinstalls.
class ExcludedImage {
  final String theme;
  final String filename;

  /// Where the file was when it was excluded, used to show a thumbnail in the
  /// exclusion list. May no longer exist once the cache has been cleaned.
  final String? localPath;

  const ExcludedImage({
    required this.theme,
    required this.filename,
    this.localPath,
  });

  String get key => '$theme/$filename';

  factory ExcludedImage.fromJson(Map<String, dynamic> json) => ExcludedImage(
        theme: json['theme'] as String? ?? '',
        filename: json['filename'] as String? ?? '',
        localPath: json['localPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'filename': filename,
        if (localPath != null) 'localPath': localPath,
      };
}

/// Window during which the slideshow stops on its own, typically overnight.
///
/// Stored as minutes from midnight so it is independent of the 12 / 24-hour
/// display format. A window may wrap around midnight (23:00 -> 07:00).
class QuietHours {
  final bool enabled;
  final int startMinutes;
  final int endMinutes;

  const QuietHours({
    this.enabled = false,
    this.startMinutes = 0,
    this.endMinutes = 7 * 60,
  });

  bool get isValid => startMinutes != endMinutes;

  /// True when [minutesOfDay] falls inside the window.
  bool containsMinutes(int minutesOfDay) {
    if (!enabled || !isValid) return false;
    if (startMinutes < endMinutes) {
      return minutesOfDay >= startMinutes && minutesOfDay < endMinutes;
    }
    // Wraps past midnight.
    return minutesOfDay >= startMinutes || minutesOfDay < endMinutes;
  }

  factory QuietHours.fromJson(Map<String, dynamic> json) => QuietHours(
        enabled: json['enabled'] as bool? ?? false,
        startMinutes: json['startMinutes'] as int? ?? 0,
        endMinutes: json['endMinutes'] as int? ?? 7 * 60,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  QuietHours copyWith({bool? enabled, int? startMinutes, int? endMinutes}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );
}

class AppConfig {
  String uiThemeMode;
  String language;
  bool launchOnStartup;
  bool randomMode;
  bool lockscreenEnabled;
  bool slideshowPaused;

  int cacheMaxSizeMb;

  int timeoutSeconds;

  /// Window during which the slideshow pauses itself.
  QuietHours quietHours;

  /// Images the user banned from every slot.
  List<ExcludedImage> excludedImages;

  bool skipUpdateCheck;
  bool debugMode;

  List<ScreenConfig> screens;

  AppConfig({
    this.uiThemeMode = 'dark',
    this.language = 'fr',
    this.launchOnStartup = false,
    this.randomMode = true,
    this.lockscreenEnabled = false,
    this.slideshowPaused = false,
    this.cacheMaxSizeMb = 500,
    this.timeoutSeconds = 10,
    this.quietHours = const QuietHours(),
    this.excludedImages = const [],
    this.skipUpdateCheck = false,
    this.debugMode = false,
    this.screens = const [],
  });

  int get cacheMaxSizeBytes => cacheMaxSizeMb * 1024 * 1024;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      uiThemeMode: json['uiThemeMode'] as String? ?? 'dark',
      language: json['language'] as String? ?? 'fr',
      launchOnStartup: json['launchOnStartup'] as bool? ?? false,
      randomMode: json['randomMode'] as bool? ?? true,
      lockscreenEnabled: json['lockscreenEnabled'] as bool? ?? false,
      slideshowPaused: json['slideshowPaused'] as bool? ?? false,
      cacheMaxSizeMb: json['cacheMaxSizeMb'] as int? ?? 500,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 10,
      quietHours: json['quietHours'] is Map<String, dynamic>
          ? QuietHours.fromJson(json['quietHours'] as Map<String, dynamic>)
          : const QuietHours(),
      excludedImages: (json['excludedImages'] as List<dynamic>?)
              ?.map((e) => ExcludedImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      skipUpdateCheck: json['skipUpdateCheck'] as bool? ?? false,
      debugMode: json['debugMode'] as bool? ?? false,
      screens: (json['screens'] as List<dynamic>?)
              ?.map((s) => ScreenConfig.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'uiThemeMode': uiThemeMode,
        'language': language,
        'launchOnStartup': launchOnStartup,
        'randomMode': randomMode,
        'lockscreenEnabled': lockscreenEnabled,
        'slideshowPaused': slideshowPaused,
        'cacheMaxSizeMb': cacheMaxSizeMb,
        'timeoutSeconds': timeoutSeconds,
        'quietHours': quietHours.toJson(),
        'excludedImages': excludedImages.map((e) => e.toJson()).toList(),
        'skipUpdateCheck': skipUpdateCheck,
        'debugMode': debugMode,
        'screens': screens.map((s) => s.toJson()).toList(),
      };

  AppConfig copyWith({
    String? uiThemeMode,
    String? language,
    bool? launchOnStartup,
    bool? randomMode,
    bool? lockscreenEnabled,
    bool? slideshowPaused,
    int? cacheMaxSizeMb,
    int? timeoutSeconds,
    QuietHours? quietHours,
    List<ExcludedImage>? excludedImages,
    bool? skipUpdateCheck,
    bool? debugMode,
    List<ScreenConfig>? screens,
  }) {
    return AppConfig(
      uiThemeMode: uiThemeMode ?? this.uiThemeMode,
      language: language ?? this.language,
      launchOnStartup: launchOnStartup ?? this.launchOnStartup,
      randomMode: randomMode ?? this.randomMode,
      lockscreenEnabled: lockscreenEnabled ?? this.lockscreenEnabled,
      slideshowPaused: slideshowPaused ?? this.slideshowPaused,
      cacheMaxSizeMb: cacheMaxSizeMb ?? this.cacheMaxSizeMb,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      quietHours: quietHours ?? this.quietHours,
      excludedImages: excludedImages ?? this.excludedImages,
      skipUpdateCheck: skipUpdateCheck ?? this.skipUpdateCheck,
      debugMode: debugMode ?? this.debugMode,
      screens: screens ?? this.screens,
    );
  }
}
