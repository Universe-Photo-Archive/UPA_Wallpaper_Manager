import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../services/log_service.dart';
import '../../services/update_service.dart';

/// ListTile-like row that keeps wide controls (SegmentedButton, buttons)
/// usable on phones. A plain [ListTile] with a wide `trailing` overflows on
/// narrow screens and the layout exception blanks the whole settings list;
/// here the control wraps below the title when space is missing.
class _ResponsiveControlTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget control;

  const _ResponsiveControlTile({
    required this.leading,
    required this.title,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 480;
      if (!narrow) {
        return ListTile(
          leading: leading,
          title: Text(title),
          trailing: FittedBox(fit: BoxFit.scaleDown, child: control),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(child: Text(title)),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: control),
            ),
          ],
        ),
      );
    });
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(l10n.settingsGeneral),
          const _GeneralSettings(),
          const SizedBox(height: 24),
          _SectionHeader(l10n.settingsDisplay),
          const _DisplaySettings(),
          const SizedBox(height: 24),
          _SectionHeader(l10n.settingsCache),
          const _CacheSettings(),
          const SizedBox(height: 24),
          _SectionHeader(l10n.settingsAdvanced),
          const _AdvancedSettings(),
          const SizedBox(height: 24),
          _SectionHeader(l10n.settingsAbout),
          const _AboutSection(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// General — launch at startup, random mode for slideshow
// ---------------------------------------------------------------------------

class _GeneralSettings extends ConsumerWidget {
  const _GeneralSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(configProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            // Auto-start at login is a desktop concept; Android has no
            // equivalent the user can toggle from here.
            if (!Platform.isAndroid) ...[
              SwitchListTile(
                title: Text(l10n.settingsLaunchStartup),
                secondary: const Icon(Icons.power_settings_new_rounded),
                value: config.launchOnStartup,
                onChanged: (val) {
                  ref
                      .read(configProvider.notifier)
                      .update((c) => c.copyWith(launchOnStartup: val));
                },
              ),
              const Divider(height: 1),
            ],
            SwitchListTile(
              title: Text(l10n.settingsRandomMode),
              secondary: const Icon(Icons.shuffle_rounded),
              value: config.randomMode,
              onChanged: (val) {
                ref
                    .read(configProvider.notifier)
                    .update((c) => c.copyWith(randomMode: val));
              },
            ),
            // On Android the lock-screen option lives here (on Windows it is
            // the toggle in the home banner, gated by admin + edition).
            if (Platform.isAndroid) ...[
              const Divider(height: 1),
              const _AndroidLockscreenTile(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Android-only: rotate the lock-screen photo along with the wallpaper.
class _AndroidLockscreenTile extends ConsumerWidget {
  const _AndroidLockscreenTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(configProvider);
    final support = ref.watch(lockscreenSupportProvider).valueOrNull;
    final supported = support?.isSupported ?? false;

    return SwitchListTile(
      title: Text(l10n.lockscreen),
      subtitle: Text(l10n.settingsLockscreenAndroidSubtitle),
      secondary: const Icon(Icons.lock_outline_rounded),
      value: supported && config.lockscreenEnabled,
      onChanged: supported
          ? (val) {
              ref
                  .read(configProvider.notifier)
                  .update((c) => c.copyWith(lockscreenEnabled: val));
            }
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Display — UI theme & language
// ---------------------------------------------------------------------------

class _DisplaySettings extends ConsumerWidget {
  const _DisplaySettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(configProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            _ResponsiveControlTile(
              leading: const Icon(Icons.palette_outlined),
              title: l10n.settingsUiTheme,
              control: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'dark',
                      label: Text(l10n.settingsThemeDark),
                      icon: const Icon(Icons.dark_mode_outlined)),
                  ButtonSegment(
                      value: 'light',
                      label: Text(l10n.settingsThemeLight),
                      icon: const Icon(Icons.light_mode_outlined)),
                  ButtonSegment(
                      value: 'system',
                      label: Text(l10n.settingsThemeSystem),
                      icon: const Icon(Icons.auto_mode_outlined)),
                ],
                selected: {config.uiThemeMode},
                onSelectionChanged: (sel) {
                  ref
                      .read(configProvider.notifier)
                      .update((c) => c.copyWith(uiThemeMode: sel.first));
                },
              ),
            ),
            const Divider(height: 1),
            _ResponsiveControlTile(
              leading: const Icon(Icons.language_rounded),
              title: l10n.settingsLanguage,
              control: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fr', label: Text('Français')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {config.language},
                onSelectionChanged: (sel) {
                  ref
                      .read(configProvider.notifier)
                      .update((c) => c.copyWith(language: sel.first));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cache — max size & clear
// ---------------------------------------------------------------------------

class _CacheSettings extends ConsumerWidget {
  const _CacheSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(configProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: Text(l10n.settingsCacheMaxSize),
              trailing: SizedBox(
                width: 100,
                child: TextField(
                  controller: TextEditingController(
                      text: config.cacheMaxSizeMb.toString()),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'MB',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onChanged: (val) {
                    final size = int.tryParse(val);
                    if (size != null && size > 0) {
                      ref
                          .read(configProvider.notifier)
                          .update((c) => c.copyWith(cacheMaxSizeMb: size));
                    }
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            _ResponsiveControlTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: l10n.settingsClearCache,
              control: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _clearCache(context, ref),
                child: Text(l10n.settingsClearCache),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsClearCache),
        content: Text(l10n.settingsClearCacheConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.dialogConfirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(cacheServiceProvider).clearCache();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsCacheCleared)),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Advanced — networking, updates, debug logs
// ---------------------------------------------------------------------------

class _AdvancedSettings extends ConsumerWidget {
  const _AdvancedSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(configProvider);
    final logService = ref.watch(logServiceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(l10n.settingsRateLimit),
              trailing: SizedBox(
                width: 80,
                child: TextField(
                  controller: TextEditingController(
                      text: config.rateLimitSeconds.toString()),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 's',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onChanged: (val) {
                    final rate = double.tryParse(val);
                    if (rate != null && rate > 0) {
                      ref.read(configProvider.notifier).update(
                          (c) => c.copyWith(rateLimitSeconds: rate));
                    }
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l10n.settingsTimeout),
              trailing: SizedBox(
                width: 80,
                child: TextField(
                  controller: TextEditingController(
                      text: config.timeoutSeconds.toString()),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 's',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onChanged: (val) {
                    final t = int.tryParse(val);
                    if (t != null && t > 0) {
                      ref.read(configProvider.notifier).update(
                          (c) => c.copyWith(timeoutSeconds: t));
                    }
                  },
                ),
              ),
            ),
            // Android updates go through the Play Store, not GitHub releases.
            if (!Platform.isAndroid) ...[
              const Divider(height: 1),
              _ResponsiveControlTile(
                leading: const Icon(Icons.system_update_outlined),
                title: l10n.updateButton,
                control: ElevatedButton.icon(
                  onPressed: () => _checkUpdates(context, ref),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.updateButton),
                ),
              ),
            ],
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.settingsDebugMode),
              value: config.debugMode,
              onChanged: (val) {
                ref
                    .read(configProvider.notifier)
                    .update((c) => c.copyWith(debugMode: val));
              },
            ),
            const Divider(height: 1),
            _LogsTile(logService: logService),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdates(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final updateService = ref.read(updateServiceProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.updateChecking)),
    );

    final info = await updateService.checkForUpdates();
    if (!context.mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.updateError)),
      );
      return;
    }

    if (!info.updateAvailable) {
      final currentVersion = await updateService.getCurrentVersion();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.updateUpToDate(currentVersion))),
      );
      return;
    }

    final currentVersion = await updateService.getCurrentVersion();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.updateTitle),
        content: Text(l10n.updateMessage(currentVersion, info.latestVersion)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.updateLater),
          ),
          if (info.downloadUrl != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _performUpdate(context, ref, info);
              },
              child: Text(l10n.updateNow),
            ),
        ],
      ),
    );
  }

  Future<void> _performUpdate(
      BuildContext context, WidgetRef ref, UpdateInfo info) async {
    if (info.downloadUrl == null) return;
    final updateService = ref.read(updateServiceProvider);
    await updateService.downloadAndInstall(info.downloadUrl!);
  }
}

// ---------------------------------------------------------------------------
// Logs tile — exposes the log file path + open / view actions
// ---------------------------------------------------------------------------

class _LogsTile extends StatelessWidget {
  final LogService logService;
  const _LogsTile({required this.logService});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.article_outlined),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l10n.settingsLogsTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.settingsLogsPath,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        logService.isInitialized ? logService.logFilePath : '—',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.settingsLogsCopyPath,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () => _copyPath(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showLogViewer(context),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(l10n.settingsLogsView),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openInOs(context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l10n.settingsLogsOpenInOs),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openFolder(context),
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: Text(l10n.settingsLogsOpenFolder),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyPath(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    if (!logService.isInitialized) return;
    await Clipboard.setData(ClipboardData(text: logService.logFilePath));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsLogsPathCopied)),
    );
  }

  Future<void> _openInOs(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    var ok = await logService.openInOs();
    if (!ok) {
      // Fallback: try url_launcher with file:// scheme.
      try {
        ok = await launchUrl(Uri.file(logService.logFilePath));
      } catch (_) {
        ok = false;
      }
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsLogsCannotOpen)),
      );
    }
  }

  Future<void> _openFolder(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await logService.openFolderInOs();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsLogsCannotOpen)),
      );
    }
  }

  void _showLogViewer(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _LogViewerDialog(logService: logService),
    );
  }
}

class _LogViewerDialog extends StatefulWidget {
  final LogService logService;
  const _LogViewerDialog({required this.logService});

  @override
  State<_LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<_LogViewerDialog> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final content = await widget.logService.readTail(maxLines: 1000);
    if (!mounted) return;
    setState(() {
      _content = content;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsLogsClear),
        content: Text(l10n.settingsLogsClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.dialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.logService.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsLogsCleared)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width * 0.9,
          maxHeight: size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.article_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsLogsTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.settingsLogsRefresh,
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: l10n.manageThemesClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                widget.logService.logFilePath,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : (_content.trim().isEmpty
                          ? Center(
                              child: Text(
                                l10n.settingsLogsEmpty,
                                style: theme.textTheme.bodyMedium,
                              ),
                            )
                          : Scrollbar(
                              child: SingleChildScrollView(
                                reverse: true,
                                child: SelectableText(
                                  _content,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : _clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.settingsLogsClear),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.dialogOk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wallpaper_rounded,
                    size: 40, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.appTitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(l10n.appVersion('2.0.0'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.aboutDescription,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                      Uri.parse('https://universe-photo-archive.eu')),
                  icon: const Icon(Icons.language_rounded, size: 16),
                  label: Text(l10n.aboutWebsite),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(
                      'https://github.com/Universe-Photo-Archive/UPA_Wallpaper_Manager')),
                  icon: const Icon(Icons.code_rounded, size: 16),
                  label: Text(l10n.aboutGithub),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
