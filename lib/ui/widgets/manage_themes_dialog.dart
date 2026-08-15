import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theme_category.dart';
import '../../providers/app_providers.dart';

/// Multi-step modal dialog to add or remove user-managed themes.
///
/// Uses [showDialog] (the same pattern as the per-screen wallpaper picker)
/// so the dialog is anchored inside the application window and cannot be
/// dragged outside of it.
class ManageThemesDialog extends ConsumerStatefulWidget {
  const ManageThemesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const ManageThemesDialog(),
    );
  }

  @override
  ConsumerState<ManageThemesDialog> createState() => _ManageThemesDialogState();
}

enum _Step { chooseAction, chooseProvider, enterUrl, removeList }

class _ManageThemesDialogState extends ConsumerState<ManageThemesDialog> {
  _Step _step = _Step.chooseAction;
  final TextEditingController _urlController = TextEditingController();
  bool _validating = false;
  String? _errorKey;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _translateError(AppLocalizations l10n, String key,
      {bool local = false}) {
    switch (key) {
      case 'invalidUrl':
        return local ? l10n.manageThemesInvalidFolder : l10n.manageThemesInvalidUrl;
      case 'alreadyExists':
        return l10n.manageThemesAlreadyExists;
      case 'apiBlocked':
        return l10n.manageThemesApiBlocked;
      case 'addFailed':
      default:
        return local ? l10n.manageThemesNoImagesInFolder : l10n.manageThemesAddFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              title: l10n.manageThemesTitle,
              showBack: _step != _Step.chooseAction,
              onBack: _goBack,
              onClose: () => Navigator.of(context).pop(),
            ),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildBody(l10n),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goBack() {
    setState(() {
      _errorKey = null;
      switch (_step) {
        case _Step.chooseProvider:
          _step = _Step.chooseAction;
          break;
        case _Step.enterUrl:
          _step = _Step.chooseProvider;
          break;
        case _Step.removeList:
          _step = _Step.chooseAction;
          break;
        case _Step.chooseAction:
          break;
      }
    });
  }

  Widget _buildBody(AppLocalizations l10n) {
    switch (_step) {
      case _Step.chooseAction:
        return _ChooseActionView(
          key: const ValueKey('choose-action'),
          l10n: l10n,
          onAdd: () => setState(() => _step = _Step.chooseProvider),
          onRemove: () => setState(() => _step = _Step.removeList),
        );
      case _Step.chooseProvider:
        return _ChooseProviderView(
          key: const ValueKey('choose-provider'),
          l10n: l10n,
          onPickLocal: _onPickLocalFolder,
          onPickPiwigo: () => setState(() {
            _step = _Step.enterUrl;
            _errorKey = null;
            _urlController.clear();
          }),
        );
      case _Step.enterUrl:
        return _EnterUrlView(
          key: const ValueKey('enter-url'),
          l10n: l10n,
          controller: _urlController,
          validating: _validating,
          errorMessage:
              _errorKey == null ? null : _translateError(l10n, _errorKey!),
          onSubmit: _onValidateUrl,
        );
      case _Step.removeList:
        return _RemoveListView(
          key: const ValueKey('remove-list'),
          l10n: l10n,
        );
    }
  }

  Future<void> _onPickLocalFolder() async {
    final l10n = AppLocalizations.of(context)!;

    if (Platform.isAndroid) {
      try {
        await Permission.photos.request();
        await Permission.storage.request();
      } catch (_) {}
    }

    String? folderPath;
    try {
      folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.manageThemesLocalPickFolder,
      );
    } catch (_) {
      folderPath = null;
    }

    // On Android, SAF folder paths are often unreadable by Dart's
    // Directory.list. Fall back to picking individual images and copying
    // them into the app's private storage so rotation can use them.
    if (Platform.isAndroid && (folderPath == null || folderPath.isEmpty)) {
      folderPath = await _importPickedImages();
    } else if (Platform.isAndroid && folderPath != null) {
      final dir = Directory(folderPath);
      var readable = false;
      try {
        readable = dir.existsSync() && dir.listSync().isNotEmpty;
      } catch (_) {
        readable = false;
      }
      if (!readable) {
        folderPath = await _importPickedImages();
      }
    }

    if (folderPath == null || !mounted) return;

    setState(() {
      _validating = true;
      _errorKey = null;
    });

    final manager = ref.read(themesManagerProvider);
    var errorKey = await manager.addLocalThemeFromFolder(folderPath);

    if (!mounted) return;

    setState(() {
      _validating = false;
      _errorKey = errorKey;
    });

    if (errorKey == 'addFailed' && Platform.isAndroid) {
      final imported = await _importPickedImages();
      if (imported != null && mounted) {
        errorKey = await manager.addLocalThemeFromFolder(imported);
        if (mounted) {
          setState(() => _errorKey = errorKey);
        }
      }
    }

    if (!mounted) return;

    if (errorKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.manageThemesAdded)),
      );
      Navigator.of(context).pop();
    } else {
      // Inline feedback on the provider screen.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translateError(l10n, errorKey, local: true)),
        ),
      );
    }
  }

  /// Lets the user pick image files and copies them into a private folder
  /// the app can always read (works around Android SAF folder paths).
  Future<String?> _importPickedImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final support = await getApplicationSupportDirectory();
    final dest = Directory(p.join(
      support.path,
      'local_themes',
      'import_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await dest.create(recursive: true);

    var copied = 0;
    for (final file in result.files) {
      final srcPath = file.path;
      if (srcPath == null || srcPath.isEmpty) continue;
      try {
        await File(srcPath).copy(p.join(dest.path, file.name));
        copied += 1;
      } catch (_) {}
    }
    if (copied == 0) return null;
    return dest.path;
  }

  Future<void> _onValidateUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorKey = 'invalidUrl');
      return;
    }

    setState(() {
      _validating = true;
      _errorKey = null;
    });

    final manager = ref.read(themesManagerProvider);
    final errorKey = await manager.addPiwigoThemeFromUrl(url);

    if (!mounted) return;

    setState(() {
      _validating = false;
      _errorKey = errorKey;
    });

    if (errorKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.manageThemesAdded)),
      );
      Navigator.of(context).pop();
    }
  }
}

class _Header extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.showBack,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: showBack ? onBack : null,
            tooltip: showBack ? AppLocalizations.of(context)!.manageThemesBack : null,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
            tooltip: AppLocalizations.of(context)!.manageThemesClose,
          ),
        ],
      ),
    );
  }
}

class _ChooseActionView extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _ChooseActionView({
    super.key,
    required this.l10n,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.manageThemesChooseAction,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _BigChoiceTile(
            icon: Icons.add_circle_outline_rounded,
            label: l10n.manageThemesAdd,
            color: Theme.of(context).colorScheme.primary,
            onTap: onAdd,
          ),
          const SizedBox(height: 12),
          _BigChoiceTile(
            icon: Icons.remove_circle_outline_rounded,
            label: l10n.manageThemesRemove,
            color: Theme.of(context).colorScheme.error,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ChooseProviderView extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback onPickLocal;
  final VoidCallback onPickPiwigo;

  const _ChooseProviderView({
    super.key,
    required this.l10n,
    required this.onPickLocal,
    required this.onPickPiwigo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.manageThemesChooseProvider,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _ProviderTile(
            icon: Icons.folder_rounded,
            title: l10n.manageThemesProviderLocal,
            subtitle: l10n.manageThemesLocalDescription,
            onTap: onPickLocal,
          ),
          const SizedBox(height: 12),
          _ProviderTile(
            icon: Icons.collections_rounded,
            title: l10n.manageThemesProviderPiwigo,
            subtitle: l10n.manageThemesPiwigoDescription,
            onTap: onPickPiwigo,
          ),
        ],
      ),
    );
  }
}

class _EnterUrlView extends StatelessWidget {
  final AppLocalizations l10n;
  final TextEditingController controller;
  final bool validating;
  final String? errorMessage;
  final Future<void> Function() onSubmit;

  const _EnterUrlView({
    super.key,
    required this.l10n,
    required this.controller,
    required this.validating,
    required this.errorMessage,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.manageThemesEnterUrl,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: !validating,
            decoration: InputDecoration(
              hintText: 'https://...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link_rounded),
              errorText: errorMessage,
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.manageThemesUrlHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (validating) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Text(l10n.manageThemesValidating),
              ],
              FilledButton.icon(
                onPressed: validating ? null : () => onSubmit(),
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.manageThemesValidate),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RemoveListView extends ConsumerWidget {
  final AppLocalizations l10n;

  const _RemoveListView({super.key, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = ref.watch(themesProvider);
    final userThemes = themes.where((t) => t.isUserAdded).toList();

    if (userThemes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.manageThemesNoUserThemes,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.manageThemesUserThemesList,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: userThemes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final t = userThemes[index];
                return _UserThemeTile(
                  theme: t,
                  onRemove: () => _confirmRemove(context, ref, t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, ThemeCategory theme) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.manageThemesRemoveConfirm),
        content: Text(theme.displayName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.manageThemesDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(themesManagerProvider).removeUserTheme(theme);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.manageThemesRemoved)),
        );
      }
    }
  }
}

class _UserThemeTile extends StatelessWidget {
  final ThemeCategory theme;
  final VoidCallback onRemove;

  const _UserThemeTile({required this.theme, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.collections_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(theme.displayName),
        subtitle: Text(
          theme.originalUrl ?? theme.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: AppLocalizations.of(context)!.manageThemesDelete,
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class _BigChoiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BigChoiceTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProviderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
