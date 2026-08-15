class ScreenConfig {
  final int screenId;
  String themeName;
  bool rotationEnabled;
  int rotationDelay;
  String rotationDelayUnit; // 'seconds', 'minutes', 'hours'
  String? currentWallpaperPath;

  ScreenConfig({
    required this.screenId,
    this.themeName = 'all',
    this.rotationEnabled = true,
    this.rotationDelay = 15,
    this.rotationDelayUnit = 'minutes',
    this.currentWallpaperPath,
  });

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
    return ScreenConfig(
      screenId: json['screenId'] as int,
      themeName: json['themeName'] as String? ?? 'all',
      rotationEnabled: json['rotationEnabled'] as bool? ?? true,
      rotationDelay: json['rotationDelay'] as int? ?? 15,
      rotationDelayUnit: json['rotationDelayUnit'] as String? ?? 'minutes',
      currentWallpaperPath: json['currentWallpaperPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'screenId': screenId,
        'themeName': themeName,
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
    String? themeName,
    bool? rotationEnabled,
    int? rotationDelay,
    String? rotationDelayUnit,
    String? currentWallpaperPath,
  }) {
    return ScreenConfig(
      screenId: screenId,
      themeName: themeName ?? this.themeName,
      rotationEnabled: rotationEnabled ?? this.rotationEnabled,
      rotationDelay: rotationDelay ?? this.rotationDelay,
      rotationDelayUnit: rotationDelayUnit ?? this.rotationDelayUnit,
      currentWallpaperPath: currentWallpaperPath ?? this.currentWallpaperPath,
    );
  }
}

class AppConfig {
  String uiThemeMode;
  String language;
  bool launchOnStartup;
  bool randomMode;
  bool lockscreenEnabled;
  bool slideshowPaused;

  int cacheMaxSizeMb;

  double rateLimitSeconds;
  int timeoutSeconds;

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
    this.rateLimitSeconds = 1.0,
    this.timeoutSeconds = 10,
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
      rateLimitSeconds: (json['rateLimitSeconds'] as num?)?.toDouble() ?? 1.0,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 10,
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
        'rateLimitSeconds': rateLimitSeconds,
        'timeoutSeconds': timeoutSeconds,
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
    double? rateLimitSeconds,
    int? timeoutSeconds,
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
      rateLimitSeconds: rateLimitSeconds ?? this.rateLimitSeconds,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      skipUpdateCheck: skipUpdateCheck ?? this.skipUpdateCheck,
      debugMode: debugMode ?? this.debugMode,
      screens: screens ?? this.screens,
    );
  }
}
