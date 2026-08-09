import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final bool updateAvailable;

  const UpdateInfo({
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    required this.updateAvailable,
  });
}

class UpdateService {
  static const String githubReleasesUrl =
      'https://api.github.com/repos/Universe-Photo-Archive/UPA_Wallpaper_Manager/releases/latest';

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'UPA-Wallpaper-Manager',
    },
  ));

  String? _currentVersion;

  Future<String> getCurrentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    return _currentVersion!;
  }

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      _log.i('Checking for updates...');
      final response = await _dio.get(githubReleasesUrl);
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      final body = data['body'] as String?;

      final currentVersion = await getCurrentVersion();
      final updateAvailable = _isNewer(latestVersion, currentVersion);

      // Find the right asset for this platform
      String? downloadUrl;
      final assets = data['assets'] as List<dynamic>? ?? [];
      final suffix = _platformAssetSuffix();
      for (final asset in assets) {
        final name = (asset as Map<String, dynamic>)['name'] as String;
        if (suffix != null && name.toLowerCase().contains(suffix)) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (updateAvailable) {
        _log.i('Update available: $latestVersion (current: $currentVersion)');
      } else {
        _log.i('App is up to date ($currentVersion)');
      }

      return UpdateInfo(
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: body,
        updateAvailable: updateAvailable,
      );
    } catch (e) {
      _log.e('Update check failed: $e');
      return null;
    }
  }

  Future<bool> downloadAndInstall(
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filename = downloadUrl.split('/').last;
      final filePath = '${tempDir.path}/$filename';

      await _dio.download(
        downloadUrl,
        filePath,
        onReceiveProgress: onProgress,
      );

      if (!File(filePath).existsSync()) return false;

      if (Platform.isWindows) {
        await Process.start(filePath, [], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else if (Platform.isLinux) {
        await Process.run('chmod', ['+x', filePath]);
        await Process.start(filePath, [], mode: ProcessStartMode.detached);
      } else if (Platform.isAndroid) {
        // On Android, use intent to install APK
        final uri = Uri.file(filePath);
        await launchUrl(uri);
      }

      return true;
    } catch (e) {
      _log.e('Update download/install failed: $e');
      return false;
    }
  }

  bool _isNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (_) {
      return false;
    }
  }

  String? _platformAssetSuffix() {
    if (Platform.isWindows) return '.exe';
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isLinux) return '.appimage';
    if (Platform.isAndroid) return '.apk';
    return null;
  }
}
