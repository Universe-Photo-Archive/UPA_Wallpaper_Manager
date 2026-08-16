import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../platform/wallpaper_channel.dart';

/// Keeps the Android background rotation in sync with the app state.
///
/// The rotation that happens while the app is closed is a WorkManager job
/// (see `RotationWorker.kt`): Android 14 has no foreground service type for
/// "change the wallpaper every N minutes", and the `specialUse` catch-all
/// needs a Play Store review. WorkManager never runs a job more often than
/// every 15 minutes, so shorter delays only apply while the app is open.
///
/// The job cannot call into Dart, so everything it needs — whether rotation is
/// enabled, the lock-screen preference and the list of already-downloaded
/// images — is written to a small JSON file it reads on wake-up.
class BackgroundRotationService {
  static const String _fileName = 'rotation_state.json';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Future<File> _stateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Writes the state file and (re)schedules or cancels the periodic job.
  ///
  /// [images] must be absolute paths of images already on disk — the job runs
  /// without network access.
  Future<void> sync({
    required bool enabled,
    required int intervalMinutes,
    required bool lockscreen,
    required List<String> images,
    String? current,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      final file = await _stateFile();
      await file.writeAsString(json.encode({
        'enabled': enabled,
        'lockscreen': lockscreen,
        'images': images,
        if (current != null) 'current': current,
      }));

      if (enabled && images.isNotEmpty) {
        await WallpaperChannel.schedulePeriodicRotation(
          intervalMinutes: intervalMinutes,
          statePath: file.path,
        );
        _log.i('Background rotation scheduled every $intervalMinutes min '
            '(${images.length} images)');
      } else {
        await WallpaperChannel.cancelPeriodicRotation();
        _log.i('Background rotation cancelled');
      }
    } catch (e) {
      _log.w('Failed to sync background rotation state: $e');
    }
  }

  /// Wallpaper the background job applied last, so the app can seed its
  /// preview with what is actually on screen. Null when unknown.
  Future<String?> lastAppliedWallpaper() async {
    if (!Platform.isAndroid) return null;
    try {
      final file = await _stateFile();
      if (!await file.exists()) return null;
      final data = json.decode(await file.readAsString());
      if (data is! Map) return null;
      final current = data['current'] as String?;
      if (current == null || current.isEmpty) return null;
      return await File(current).exists() ? current : null;
    } catch (_) {
      return null;
    }
  }
}
