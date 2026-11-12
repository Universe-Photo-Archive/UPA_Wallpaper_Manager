import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/app_config.dart';

/// Everything the user configured, in one file they can carry to another
/// device: settings, the galleries they added, and the photos they banned.
class SettingsTransferService {
  /// Marks a file as ours. Refusing anything else is what keeps an unrelated
  /// JSON from silently wiping someone's settings.
  static const String formatId = 'upa-wallpaper-manager-settings';
  static const int formatVersion = 1;

  Map<String, dynamic> buildPayload({
    required AppConfig config,
    required Map<String, dynamic> themes,
    required String appVersion,
  }) {
    return {
      'format': formatId,
      'formatVersion': formatVersion,
      'appVersion': appVersion,
      // The platform decides whether the folder themes can be imported: a
      // path or an Android permission does not travel to another machine.
      'platform': Platform.operatingSystem,
      'exportedAt': DateTime.now().toIso8601String(),
      'config': config.toJson(),
      'themes': themes,
    };
  }

  /// Reads a payload, or throws [FormatException] when the file is not one
  /// of ours.
  SettingsPayload parse(String raw) {
    final dynamic decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      throw const FormatException('not JSON');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != formatId) {
      throw const FormatException('not an export of this app');
    }
    final version = decoded['formatVersion'] as int? ?? 0;
    if (version > formatVersion) {
      throw const FormatException('written by a newer version');
    }

    final configJson = decoded['config'];
    if (configJson is! Map<String, dynamic>) {
      throw const FormatException('no settings inside');
    }

    return SettingsPayload(
      config: AppConfig.fromJson(configJson),
      themes: (decoded['themes'] as Map<String, dynamic>?) ?? const {},
      platform: decoded['platform'] as String? ?? '',
      exportedAt: DateTime.tryParse(decoded['exportedAt'] as String? ?? ''),
      appVersion: decoded['appVersion'] as String? ?? '',
    );
  }

  String suggestedFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'upa-wallpaper-manager-'
        '${now.year}${two(now.month)}${two(now.day)}.json';
  }

  /// Asks where to write the export and does it. Returns the file, or null
  /// when the user changed their mind.
  Future<String?> saveToFile(Map<String, dynamic> payload) async {
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );

    // The picker writes the bytes itself on every platform.
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export',
      fileName: suggestedFileName(),
      mimeType: 'application/json',
      bytes: bytes,
    );
    if (uri == null) return null;
    return _displayName(uri);
  }

  /// Reads a file the user picks. Null when they cancel.
  Future<String?> readPickedFile() async {
    // Android file managers routinely hide files whose type they do not
    // recognise, so ask for anything and let [parse] reject what is not ours.
    final file = await FilePicker.pickFile(
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const ['json'],
    );
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  /// A path the user can recognise. Android hands back a storage-framework
  /// `content://` URI whose last segment reads like `primary:Download/x.json`.
  String _displayName(Uri uri) {
    if (uri.scheme == 'file') return uri.toFilePath();
    if (uri.pathSegments.isEmpty) return uri.toString();
    final last = Uri.decodeComponent(uri.pathSegments.last);
    final colon = last.indexOf(':');
    return colon >= 0 ? last.substring(colon + 1) : last;
  }
}

class SettingsPayload {
  final AppConfig config;
  final Map<String, dynamic> themes;
  final String platform;
  final DateTime? exportedAt;
  final String appVersion;

  const SettingsPayload({
    required this.config,
    required this.themes,
    required this.platform,
    required this.exportedAt,
    required this.appVersion,
  });

  /// Folder themes only make sense back on the system they were read from:
  /// elsewhere the path does not exist, or the permission was never granted.
  bool get carriesUsableLocalThemes => platform == Platform.operatingSystem;
}