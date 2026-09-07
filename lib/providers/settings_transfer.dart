import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_config.dart';
import '../services/settings_transfer_service.dart';
import 'app_providers.dart';

/// Carries a whole setup — settings, added galleries, banned photos — out to
/// a file and back in, on any platform.
final settingsTransferProvider = Provider<SettingsTransferManager>((ref) {
  return SettingsTransferManager(ref, SettingsTransferService());
});

enum ImportMode {
  /// Everything from the file wins.
  replace,

  /// Only adds: galleries and banned photos join the ones already here.
  merge,
}

class TransferResult {
  final bool done;

  /// Where the export landed, for the message shown afterwards.
  final String? path;
  final String? error;

  const TransferResult.saved(this.path) : done = true, error = null;
  const TransferResult.cancelled() : done = false, path = null, error = null;
  const TransferResult.failed(this.error) : done = false, path = null;
}

class SettingsTransferManager {
  final Ref _ref;
  final SettingsTransferService _service;

  SettingsTransferManager(this._ref, this._service);

  Future<TransferResult> export() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final payload = _service.buildPayload(
        config: _ref.read(configProvider),
        themes: _ref.read(themesConfigServiceProvider).userConfigSnapshot,
        appVersion: info.version,
      );
      final path = await _service.saveToFile(payload);
      if (path == null) return const TransferResult.cancelled();
      return TransferResult.saved(path);
    } catch (e) {
      return TransferResult.failed(e.toString());
    }
  }

  Future<TransferResult> import(ImportMode mode) async {
    final SettingsPayload payload;
    try {
      final raw = await _service.readPickedFile();
      if (raw == null) return const TransferResult.cancelled();
      payload = _service.parse(raw);
    } catch (e) {
      return TransferResult.failed(
        e is FormatException ? e.message : e.toString(),
      );
    }

    try {
      final themesConfig = _ref.read(themesConfigServiceProvider);
      if (mode == ImportMode.replace) {
        await themesConfig.replaceUserConfig(
          payload.themes,
          keepLocalSources: !payload.carriesUsableLocalThemes,
        );
        await _ref
            .read(configProvider.notifier)
            .update((current) => _adopt(payload.config, current));
      } else {
        await themesConfig.mergeUserConfig(
          payload.themes,
          includeLocalSources: payload.carriesUsableLocalThemes,
        );
        await _ref
            .read(configProvider.notifier)
            .update(
              (current) => current.copyWith(
                excludedImages: _mergedExclusions(current, payload.config),
              ),
            );
      }

      await _ref.read(themesManagerProvider).reloadUserThemes();
      return const TransferResult.saved(null);
    } catch (e) {
      return TransferResult.failed(e.toString());
    }
  }

  /// Takes the imported settings, minus the ones that describe this machine
  /// rather than the user's taste.
  AppConfig _adopt(AppConfig imported, AppConfig current) {
    // Screens are matched by id, and those ids mean different things on a
    // phone and on a desktop; keeping the local ones avoids a slideshow
    // pointed at a monitor that does not exist.
    return imported.copyWith(
      screens: current.screens,
      uiScale: Platform.isAndroid ? current.uiScale : imported.uiScale,
    );
  }

  List<ExcludedImage> _mergedExclusions(AppConfig current, AppConfig imported) {
    final byKey = <String, ExcludedImage>{
      for (final e in current.excludedImages) e.key: e,
    };
    for (final e in imported.excludedImages) {
      byKey.putIfAbsent(e.key, () => e);
    }
    return byKey.values.toList();
  }
}
