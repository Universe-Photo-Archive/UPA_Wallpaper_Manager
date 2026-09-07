import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_config.dart';
import '../../providers/app_providers.dart';

/// Images the user banned, laid out like the gallery so the two feel alike.
///
/// Each tile can be put back into the rotation, and the whole list can be
/// cleared at once from the bottom bar.
class ExcludedImagesScreen extends ConsumerWidget {
  const ExcludedImagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final excluded = ref.watch(configProvider).excludedImages;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.excludedTitle)),
      body: excluded.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block_outlined,
                      size: 72,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.excludedEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 1200
                    ? 5
                    : constraints.maxWidth > 900
                    ? 4
                    : constraints.maxWidth > 600
                    ? 3
                    : 2;
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    // The extra height is the caption under each photo.
                    childAspectRatio: 16 / 12,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: excluded.length,
                  itemBuilder: (context, index) => _ExcludedTile(
                    image: excluded[index],
                    title: ref
                        .read(cacheServiceProvider)
                        .titleFor(
                          excluded[index].theme,
                          excluded[index].filename,
                        ),
                    onRestore: () => _restore(context, ref, excluded[index]),
                  ),
                );
              },
            ),
      bottomNavigationBar: excluded.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () => _clearAll(context, ref),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(l10n.excludedClearAll),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            ),
    );
  }

  void _restore(BuildContext context, WidgetRef ref, ExcludedImage image) {
    final l10n = AppLocalizations.of(context)!;
    ref.read(exclusionsProvider).restore(image);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.excludedRestored)));
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.excludedClearAll),
        content: Text(l10n.excludedClearConfirm),
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
            child: Text(l10n.dialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(exclusionsProvider).clear();
    }
  }
}

class _ExcludedTile extends StatelessWidget {
  final ExcludedImage image;

  /// Piwigo title, when the photo is still known to the cache.
  final String? title;
  final VoidCallback onRestore;

  const _ExcludedTile({
    required this.image,
    required this.title,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final path = image.localPath;
    final available = path != null && File(path).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (available)
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 500,
                    errorBuilder: (_, __, ___) => _Missing(),
                  )
                else
                  _Missing(),
                Positioned(
                  top: 4,
                  right: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: l10n.excludedRestore,
                      icon: const Icon(
                        Icons.restore_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      onPressed: onRestore,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title ?? _withoutExtension(image.filename),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// The banned photos keep their file name; the extension is noise.
  String _withoutExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

class _Missing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    );
  }
}
