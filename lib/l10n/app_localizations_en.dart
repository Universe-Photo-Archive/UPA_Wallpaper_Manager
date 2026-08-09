// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'UPA Wallpaper Manager';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navGallery => 'Gallery';

  @override
  String get navSettings => 'Settings';

  @override
  String get screenConfig => 'Screen Configuration';

  @override
  String get rotationDelay => 'Slideshow delay:';

  @override
  String get lockscreen => 'Also apply to lock screen';

  @override
  String get lockscreenTooltip =>
      'This option will only work if both of the following conditions are met:\n\n• The application is run as administrator.\n• A Pro / Enterprise / Education edition of Windows is installed.\n\nThe wallpaper from screen 1 is used for the lock screen.';

  @override
  String get lockscreenUnsupportedTitle =>
      'The lock screen cannot be controlled on this system:';

  @override
  String get lockscreenReasonAdmin =>
      'The application is not running as administrator.';

  @override
  String get lockscreenReasonEdition =>
      'This Windows edition (Home) does not support automatic lock screen changes. Pro / Enterprise / Education is required.';

  @override
  String get applyNow => 'Apply now';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get statusInitializing => 'Initializing...';

  @override
  String get statusLoading => 'Loading...';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusOffline => 'Offline';

  @override
  String statusThemes(int count) {
    return '$count themes';
  }

  @override
  String statusCache(String size) {
    return 'Cache: $size MB';
  }

  @override
  String get statusDownloading => 'Downloading images...';

  @override
  String get statusNoImages => 'No images found';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusNewDelay => 'New delay configured — Click \"Apply now\"';

  @override
  String get statusLockscreenEnabled => 'Lock screen enabled';

  @override
  String get statusLockscreenDisabled =>
      'Lock screen disabled — control returned to OS';

  @override
  String get statusLockscreenAdmin =>
      'Relaunch as admin to fully disable lock screen';

  @override
  String get timeSeconds => 'seconds';

  @override
  String get timeMinutes => 'minutes';

  @override
  String get timeHours => 'hours';

  @override
  String screenName(int id) {
    return 'Screen $id';
  }

  @override
  String get screenPrimary => 'Primary';

  @override
  String get screenRotationEnabled => 'Slideshow enabled';

  @override
  String get screenTheme => 'Theme:';

  @override
  String get screenAllThemes => 'All themes';

  @override
  String get screenResolution => 'Resolution:';

  @override
  String get screenCurrentWallpaper => 'Current wallpaper:';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsApply => 'Apply';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsCache => 'Cache';

  @override
  String get settingsAdvanced => 'Advanced';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLaunchStartup => 'Launch at system startup';

  @override
  String get settingsUiTheme => 'Interface theme:';

  @override
  String get settingsLanguage => 'Language:';

  @override
  String get settingsRandomMode => 'Random mode for slideshow';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsCacheMaxSize => 'Maximum cache size (MB):';

  @override
  String get settingsCacheCurrent => 'Current cache size:';

  @override
  String get settingsCacheCalculating => 'Calculating cache size...';

  @override
  String get settingsClearCache => 'Clear cache';

  @override
  String get settingsReloadThemes => 'Reload themes';

  @override
  String get settingsCacheCleared => 'Cache cleared successfully!';

  @override
  String get settingsThemesReloaded => 'Themes reloaded!';

  @override
  String get settingsClearCacheConfirm =>
      'Are you sure you want to clear the cache?';

  @override
  String get settingsRateLimit => 'Delay between requests (seconds):';

  @override
  String get settingsTimeout => 'Network timeout (seconds):';

  @override
  String get settingsDebugMode => 'Debug mode (detailed logs)';

  @override
  String get settingsLogsTitle => 'Log file';

  @override
  String get settingsLogsPath => 'Location:';

  @override
  String get settingsLogsView => 'View logs';

  @override
  String get settingsLogsOpenInOs => 'Open in system editor';

  @override
  String get settingsLogsOpenFolder => 'Open folder';

  @override
  String get settingsLogsClear => 'Clear logs';

  @override
  String get settingsLogsCleared => 'Logs cleared';

  @override
  String get settingsLogsClearConfirm =>
      'Are you sure you want to clear the log file?';

  @override
  String get settingsLogsEmpty => 'The log file is empty for now.';

  @override
  String get settingsLogsCopyPath => 'Copy path';

  @override
  String get settingsLogsPathCopied => 'Path copied to clipboard';

  @override
  String get settingsLogsRefresh => 'Refresh';

  @override
  String get settingsLogsCannotOpen => 'Could not open the log file';

  @override
  String errorGeneral(String message) {
    return 'Error: $message';
  }

  @override
  String get errorNetwork => 'Network error. Check your connection.';

  @override
  String get errorCache => 'Cache error.';

  @override
  String get updateTitle => 'Update available';

  @override
  String updateMessage(String current, String latest) {
    return 'A new version ($latest) is available.\n\nCurrent version: $current\nNew version: $latest';
  }

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Next time';

  @override
  String get updateSkip => 'Don\'t ask again';

  @override
  String get updateButton => 'Check for updates';

  @override
  String get updateChecking => 'Checking for updates...';

  @override
  String get updateDownloading => 'Downloading update...';

  @override
  String get updateInstalling => 'Installing...';

  @override
  String get updateSuccess =>
      'Update downloaded! The application will close to install the new version.';

  @override
  String get updateNoUpdate => 'No update available';

  @override
  String updateUpToDate(String version) {
    return 'Your application is up to date (version $version)';
  }

  @override
  String get updateError => 'Error checking for updates';

  @override
  String get galleryTitle => 'Gallery';

  @override
  String get galleryEmpty => 'No images in this theme';

  @override
  String get gallerySetWallpaper => 'Set as wallpaper';

  @override
  String get gallerySetLockscreen => 'Set as lock screen';

  @override
  String get gallerySaveToDevice => 'Save to device';

  @override
  String get galleryDownloading => 'Downloading...';

  @override
  String get gallerySelectThemeHint => 'Select a theme to browse wallpapers';

  @override
  String get galleryAllScreens => 'All screens';

  @override
  String get galleryWallpaperApplied => 'Wallpaper applied!';

  @override
  String get galleryWallpaperAppliedAll => 'Wallpaper applied on all screens!';

  @override
  String get galleryWallpaperFailed => 'Failed to apply wallpaper';

  @override
  String get manageThemes => 'Manage themes';

  @override
  String get manageThemesTitle => 'Theme management';

  @override
  String get manageThemesAdd => 'Add a theme';

  @override
  String get manageThemesRemove => 'Remove a theme';

  @override
  String get manageThemesChooseAction => 'What would you like to do?';

  @override
  String get manageThemesChooseProvider => 'Choose a photo provider';

  @override
  String get manageThemesProviderPiwigo => 'Piwigo';

  @override
  String get manageThemesPiwigoDescription => 'Album from a Piwigo gallery';

  @override
  String get manageThemesProviderLocal => 'Local gallery';

  @override
  String get manageThemesLocalDescription =>
      'A folder of images from your computer';

  @override
  String get manageThemesLocalPickFolder => 'Pick a folder of images';

  @override
  String get manageThemesInvalidFolder => 'Invalid or unreadable folder';

  @override
  String get manageThemesNoImagesInFolder => 'No images found in this folder';

  @override
  String get manageThemesEnterUrl => 'Piwigo album URL';

  @override
  String get manageThemesUrlHelp =>
      'Example: https://example.com/gallery/index.php?/category/123';

  @override
  String get manageThemesValidate => 'Validate';

  @override
  String get manageThemesValidating => 'Validating...';

  @override
  String get manageThemesAdded => 'Theme added successfully';

  @override
  String get manageThemesAddFailed =>
      'Could not add this theme. Check the URL.';

  @override
  String get manageThemesInvalidUrl => 'Invalid Piwigo URL';

  @override
  String get manageThemesAlreadyExists => 'This theme already exists';

  @override
  String get manageThemesNoUserThemes => 'No manually added themes';

  @override
  String get manageThemesRemoveConfirm => 'Remove this theme?';

  @override
  String get manageThemesRemoved => 'Theme removed';

  @override
  String get manageThemesUserThemesList => 'Your added themes';

  @override
  String get manageThemesBack => 'Back';

  @override
  String get manageThemesClose => 'Close';

  @override
  String get manageThemesDelete => 'Delete';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutDescription =>
      'UPA Wallpaper Manager is a cross-platform wallpaper manager powered by the Universe Photo Archive gallery.';

  @override
  String get aboutWebsite => 'Visit website';

  @override
  String get aboutGithub => 'GitHub';

  @override
  String get aboutLicense => 'License';

  @override
  String get trayOpen => 'Open';

  @override
  String get trayChangeNow => 'Change now';

  @override
  String get trayPause => 'Pause';

  @override
  String get trayResume => 'Resume';

  @override
  String get trayQuit => 'Quit';

  @override
  String get dialogConfirm => 'Confirm';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get dialogYes => 'Yes';

  @override
  String get dialogNo => 'No';

  @override
  String get dialogOk => 'OK';
}
