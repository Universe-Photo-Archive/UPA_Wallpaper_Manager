import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../platform/wallpaper_channel.dart';

/// One rotating wallpaper slot: the home screen or the lock screen.
class RotationTargetState {
  /// Matches `RotationTarget.TARGET_*` on the native side.
  final int id;
  final bool enabled;
  final int intervalSeconds;
  final String theme;
  final List<String> images;
  final String? current;

  const RotationTargetState({
    required this.id,
    required this.enabled,
    required this.intervalSeconds,
    required this.theme,
    required this.images,
    this.current,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'intervalSeconds': intervalSeconds,
        'theme': theme,
        'images': images,
        if (current != null) 'current': current,
      };
}

/// Bridges the app settings and the Android background slideshow.
///
/// The rotation that happens while the app is closed runs natively (see
/// `RotationForegroundService.kt`), because it must keep its schedule when
/// Dart is not running at all. Everything it needs — which slot rotates, how
/// often, and the images already downloaded for it — is mirrored into a small
/// JSON file it reads on every tick.
///
/// Both sides write to that file: Dart owns the schedule, the native side owns
/// what is currently displayed and the pause flag.
class BackgroundRotationService {
  static const String _fileName = 'rotation_state.json';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Future<File> _stateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Mirrors the current settings and starts, refreshes or stops the service.
  ///
  /// [targets] must carry absolute paths of images already on disk: the
  /// background rotation never touches the network.
  Future<void> sync({
    required bool paused,
    required List<RotationTargetState> targets,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      final file = await _stateFile();
      final previous = await _read(file);

      // Keep whatever the native side recorded as displayed, unless this sync
      // provides a fresher value.
      final previousCurrent = <int, String>{};
      for (final target in (previous?['targets'] as List<dynamic>? ?? [])) {
        if (target is! Map) continue;
        final id = target['id'] as int?;
        final current = target['current'] as String?;
        if (id != null && current != null) previousCurrent[id] = current;
      }

      await file.writeAsString(json.encode({
        'paused': paused,
        'targets': [
          for (final target in targets)
            {
              ...target.toJson(),
              if (target.current == null && previousCurrent[target.id] != null)
                'current': previousCurrent[target.id],
            }
        ],
      }));

      final active = !paused &&
          targets.any((t) => t.enabled && t.images.isNotEmpty);

      if (active) {
        await WallpaperChannel.startForegroundRotation();
        // Fallback for a reboot or a manufacturer task killer: the job only
        // acts when the service is gone.
        final shortest = targets
            .where((t) => t.enabled)
            .map((t) => t.intervalSeconds)
            .fold<int>(3600, (a, b) => b < a ? b : a);
        await WallpaperChannel.schedulePeriodicRotation(
          intervalMinutes: (shortest / 60).ceil(),
        );
        _log.i('Slideshow service running (${targets.where((t) => t.enabled).length} target(s))');
      } else {
        await WallpaperChannel.stopForegroundRotation();
        await WallpaperChannel.cancelPeriodicRotation();
        _log.i('Slideshow service stopped');
      }
    } catch (e) {
      _log.w('Failed to sync background rotation state: $e');
    }
  }

  /// Records [path] as displayed on [screenId] without touching the schedule.
  Future<void> updateCurrent(int screenId, String path) async {
    if (!Platform.isAndroid) return;
    try {
      final file = await _stateFile();
      final data = await _read(file);
      if (data == null) return;
      final targets = data['targets'];
      if (targets is! List) return;
      for (final target in targets) {
        if (target is Map && target['id'] == screenId) {
          target['current'] = path;
          break;
        }
      }
      await file.writeAsString(json.encode(data));
    } catch (_) {
      // The next full sync will fix the file.
    }
  }

  /// Wallpapers the background rotation applied last, per screen id, so the
  /// app can seed its previews with what is actually displayed.
  Future<Map<int, String>> lastAppliedWallpapers() async {
    if (!Platform.isAndroid) return {};
    try {
      final data = await _read(await _stateFile());
      final targets = data?['targets'];
      if (targets is! List) return {};
      final result = <int, String>{};
      for (final target in targets) {
        if (target is! Map) continue;
        final id = target['id'] as int?;
        final current = target['current'] as String?;
        if (id == null || current == null || current.isEmpty) continue;
        if (await File(current).exists()) result[id] = current;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Pause flag as the native side left it (the notification can toggle it).
  Future<bool> isPaused() async {
    if (!Platform.isAndroid) return false;
    final data = await _read(await _stateFile());
    return data?['paused'] as bool? ?? false;
  }

  Future<Map<String, dynamic>?> _read(File file) async {
    if (!await file.exists()) return null;
    try {
      final data = json.decode(await file.readAsString());
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }
}
