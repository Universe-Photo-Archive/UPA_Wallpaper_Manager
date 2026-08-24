import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theme_source.dart';
import '../../providers/app_providers.dart';
import '../widgets/folder_chooser.dart';
import '../widgets/local_photo_picker.dart';
import '../widgets/theme_name_dialog.dart';

/// What the user asked to do with a local theme.
enum EditThemeAction { removePhotos }

/// Choices offered for a local theme: add photos, remove some, or rename.
///
/// A folder theme only gets the rename: its content mirrors the folder and is
/// refreshed on its own, so picking photos out of it would be undone at the
/// next scan.
class EditLocalThemeScreen extends ConsumerWidget {
  final LocalSource source;

  const EditLocalThemeScreen({super.key, required this.source});

  /// Returns an action for the caller to carry out, or null when everything
  /// was handled here.
  static Future<EditThemeAction?> show(
    BuildContext context, {
    required LocalSource source,
  }) {
    return Navigator.of(context).push<EditThemeAction>(
      MaterialPageRoute(
        builder: (_) => EditLocalThemeScreen(source: source),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(source.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (source.isFolder)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.editThemeFolderOnlyRename,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
            ),
          if (!source.isFolder) ...[
            _ActionTile(
              icon: Icons.add_photo_alternate_outlined,
              title: l10n.editThemeAdd,
              subtitle: l10n.editThemeAddDescription,
              onTap: () => _addPhotos(context, ref),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.remove_circle_outline_rounded,
              title: l10n.editThemeRemove,
              subtitle: l10n.editThemeRemoveDescription,
              onTap: () => Navigator.pop(context, EditThemeAction.removePhotos),
            ),
            const SizedBox(height: 12),
          ],
          _ActionTile(
            icon: Icons.drive_file_rename_outline_rounded,
            title: l10n.editThemeRename,
            subtitle: source.name,
            onTap: () => _rename(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptThemeName(context, initial: source.name);
    if (name == null || !context.mounted) return;
    await ref.read(themesManagerProvider).renameLocalTheme(source, name);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _addPhotos(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;

    // Photos may come from a folder already granted or from a new one; either
    // way the grant is what makes them readable later.
    final root = await chooseFolder(context);
    if (root == null || !context.mounted) return;

    final picked = await LocalPhotoPicker.show(
      context,
      root: root,
      alreadyIn: source.items.toSet(),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    await ref
        .read(themesManagerProvider)
        .addPhotosToTheme(source, root: root, items: picked);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.photosAdded)),
    );
    Navigator.pop(context);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
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
