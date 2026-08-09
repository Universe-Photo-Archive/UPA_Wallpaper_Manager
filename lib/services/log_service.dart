import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

/// Persistent file-based logger.
///
/// Always records important events (wallpaper changes, errors). When
/// [debugMode] is enabled, also records detailed debug entries.
///
/// The log file lives in the OS application support directory and is
/// rotated when its size exceeds [_maxBytes] (the previous file is kept
/// as `<name>.1.log`).
class LogService {
  static const String _fileName = 'upa_wallpaper.log';
  static const String _previousFileName = 'upa_wallpaper.1.log';

  /// Max size before rotation (~2 MB).
  static const int _maxBytes = 2 * 1024 * 1024;

  late final File _file;
  late final File _previousFile;
  late final Directory _dir;

  bool _initialized = false;
  bool debugMode;

  /// Serialize writes so concurrent rotations cannot interleave entries.
  Future<void> _writeQueue = Future<void>.value();

  LogService({this.debugMode = false});

  bool get isInitialized => _initialized;
  String get logFilePath => _file.path;
  String get logDirectoryPath => _dir.path;
  File get logFile => _file;

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _dir = Directory('${appDir.path}/logs');
    if (!_dir.existsSync()) {
      _dir.createSync(recursive: true);
    }
    _file = File('${_dir.path}/$_fileName');
    _previousFile = File('${_dir.path}/$_previousFileName');
    if (!_file.existsSync()) {
      _file.writeAsStringSync('');
    }
    _initialized = true;
    info('LogService initialized at ${_file.path}');
  }

  // --- Public log API ---

  void debug(String message) {
    if (!debugMode) return;
    _write(LogLevel.debug, message);
  }

  void info(String message) => _write(LogLevel.info, message);
  void warning(String message) => _write(LogLevel.warning, message);
  void error(String message, [Object? err, StackTrace? stack]) {
    final buf = StringBuffer(message);
    if (err != null) buf.write(' | $err');
    if (stack != null && debugMode) buf.write('\n$stack');
    _write(LogLevel.error, buf.toString());
  }

  /// Records a wallpaper change with all the metadata required by the UI.
  void logWallpaperChange({
    required int screenId,
    required String themeName,
    required String imagePath,
    DateTime? at,
  }) {
    final filename = imagePath
        .replaceAll('\\', '/')
        .split('/')
        .where((p) => p.isNotEmpty)
        .lastOrNull ??
        imagePath;
    final ts = at ?? DateTime.now();
    final msg =
        'WALLPAPER_CHANGE | screen=$screenId | theme="$themeName" | image="$filename"';
    _write(LogLevel.info, msg, timestamp: ts);
  }

  /// Returns the full log content (current + previous if available).
  Future<String> readAll({bool includePrevious = true}) async {
    if (!_initialized) return '';
    final buf = StringBuffer();
    if (includePrevious && await _previousFile.exists()) {
      buf.write(await _previousFile.readAsString());
    }
    if (await _file.exists()) {
      buf.write(await _file.readAsString());
    }
    return buf.toString();
  }

  /// Returns the last [maxLines] lines of the current log file.
  Future<String> readTail({int maxLines = 500}) async {
    if (!_initialized || !await _file.exists()) return '';
    final content = await _file.readAsString();
    final lines = content.split('\n');
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  }

  Future<void> clear() async {
    if (!_initialized) return;
    if (await _previousFile.exists()) {
      await _previousFile.delete();
    }
    await _file.writeAsString('');
    info('Log file cleared by user');
  }

  /// Opens the log file with the OS default text-file handler.
  /// Returns true on success.
  Future<bool> openInOs() async {
    if (!_initialized || !await _file.exists()) return false;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', _file.path],
            runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.start('open', [_file.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [_file.path]);
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the folder containing the log file.
  Future<bool> openFolderInOs() async {
    if (!_initialized) return false;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [_dir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [_dir.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [_dir.path]);
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Internals ---

  void _write(LogLevel level, String message, {DateTime? timestamp}) {
    if (!_initialized) return;
    final ts = (timestamp ?? DateTime.now()).toIso8601String();
    final tag = switch (level) {
      LogLevel.debug => 'DEBUG',
      LogLevel.info => 'INFO ',
      LogLevel.warning => 'WARN ',
      LogLevel.error => 'ERROR',
    };
    final line = '[$ts] [$tag] $message\n';

    _writeQueue = _writeQueue.then((_) async {
      try {
        await _file.writeAsString(line, mode: FileMode.append, flush: true);
        await _rotateIfNeeded();
      } catch (_) {
        // Logging must never throw upstream.
      }
    });
  }

  Future<void> _rotateIfNeeded() async {
    try {
      final size = await _file.length();
      if (size < _maxBytes) return;
      if (await _previousFile.exists()) {
        await _previousFile.delete();
      }
      await _file.rename(_previousFile.path);
      await _file.writeAsString('');
    } catch (_) {
      // Best-effort rotation.
    }
  }
}
