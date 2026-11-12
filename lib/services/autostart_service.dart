import 'dart:io';
import 'package:logger/logger.dart';

/// Cross-platform "launch at login" abstraction.
///
/// On Windows the app runs elevated (requireAdministrator manifest) and the
/// HKCU `Run` registry key silently skips programs that require elevation,
/// so a Scheduled Task with "Run with highest privileges" is used instead —
/// it starts the app elevated at logon without any UAC prompt.
/// Linux gets an XDG autostart entry. macOS has no native login-item bridge
/// yet, so it reports the feature as unavailable.
class AutostartService {
  static const String taskName = 'UPA Wallpaper Manager';
  static const String minimizedFlag = '--minimized';

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _startupApprovedKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Name the legacy `Run` value and the Linux desktop entry are keyed by.
  String _appName = 'upa_wallpaper_manager';

  void setup({required String appName}) {
    if (appName.isNotEmpty) _appName = appName;
  }

  File get _linuxDesktopFile => File(
    '${Platform.environment['HOME']}/.config/autostart/$_appName.desktop',
  );

  Future<bool> isEnabled() async {
    if (Platform.isWindows) {
      final result = await Process.run('schtasks', ['/Query', '/TN', taskName]);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) return _linuxDesktopFile.existsSync();
    return false;
  }

  Future<bool> enable() async {
    if (Platform.isWindows) {
      // Remove any legacy HKCU Run entry left by versions <= 1.x (it would
      // be silently ignored by Windows now that the app requires elevation).
      await _removeLegacyRunEntry();

      final exe = Platform.resolvedExecutable;
      final result = await Process.run('schtasks', [
        '/Create',
        '/F',
        '/TN',
        taskName,
        '/SC',
        'ONLOGON',
        '/RL',
        'HIGHEST',
        '/TR',
        '"$exe" $minimizedFlag',
      ]);
      if (result.exitCode != 0) {
        _log.w(
          'schtasks /Create failed (${result.exitCode}): '
          '${result.stderr}',
        );
        return false;
      }
      _log.i('Autostart scheduled task created');
      return true;
    }
    if (Platform.isLinux) {
      final file = _linuxDesktopFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=$_appName\n'
        'Comment=$_appName startup script\n'
        'Exec=${Platform.resolvedExecutable} $minimizedFlag\n'
        'StartupNotify=false\n'
        'Terminal=false\n',
      );
      return true;
    }
    return false;
  }

  Future<bool> disable() async {
    if (Platform.isWindows) {
      await _removeLegacyRunEntry();
      final result = await Process.run('schtasks', [
        '/Delete',
        '/F',
        '/TN',
        taskName,
      ]);
      if (result.exitCode != 0) {
        // Most common cause: the task simply does not exist.
        _log.i('schtasks /Delete returned ${result.exitCode} (task absent?)');
      }
      return true;
    }
    if (Platform.isLinux) {
      final file = _linuxDesktopFile;
      if (file.existsSync()) file.deleteSync();
      return true;
    }
    return false;
  }

  Future<void> _removeLegacyRunEntry() async {
    for (final key in const [_runKey, _startupApprovedKey]) {
      try {
        // Fails harmlessly when the value does not exist.
        await Process.run('reg', ['delete', key, '/v', _appName, '/f']);
      } catch (_) {}
    }
  }
}
