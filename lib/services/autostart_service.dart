import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:logger/logger.dart';

/// Cross-platform "launch at login" abstraction.
///
/// On Windows the app runs elevated (requireAdministrator manifest) and the
/// HKCU `Run` registry key silently skips programs that require elevation,
/// so a Scheduled Task with "Run with highest privileges" is used instead —
/// it starts the app elevated at logon without any UAC prompt.
/// Other platforms keep using the `launch_at_startup` package.
class AutostartService {
  static const String taskName = 'UPA Wallpaper Manager';
  static const String minimizedFlag = '--minimized';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Future<bool> isEnabled() async {
    if (Platform.isWindows) {
      final result = await Process.run('schtasks', ['/Query', '/TN', taskName]);
      return result.exitCode == 0;
    }
    return launchAtStartup.isEnabled();
  }

  Future<bool> enable() async {
    if (Platform.isWindows) {
      // Remove any legacy HKCU Run entry left by versions <= 1.x (it would
      // be silently ignored by Windows now that the app requires elevation).
      try {
        await launchAtStartup.disable();
      } catch (_) {}

      final exe = Platform.resolvedExecutable;
      final result = await Process.run('schtasks', [
        '/Create',
        '/F',
        '/TN', taskName,
        '/SC', 'ONLOGON',
        '/RL', 'HIGHEST',
        '/TR', '"$exe" $minimizedFlag',
      ]);
      if (result.exitCode != 0) {
        _log.w('schtasks /Create failed (${result.exitCode}): '
            '${result.stderr}');
        return false;
      }
      _log.i('Autostart scheduled task created');
      return true;
    }
    await launchAtStartup.enable();
    return true;
  }

  Future<bool> disable() async {
    if (Platform.isWindows) {
      try {
        await launchAtStartup.disable();
      } catch (_) {}
      final result =
          await Process.run('schtasks', ['/Delete', '/F', '/TN', taskName]);
      if (result.exitCode != 0) {
        // Most common cause: the task simply does not exist.
        _log.i('schtasks /Delete returned ${result.exitCode} (task absent?)');
      }
      return true;
    }
    await launchAtStartup.disable();
    return true;
  }
}
