import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isOnline = ref.watch(isOnlineProvider);
    final themes = ref.watch(themesProvider);
    final statusMsg = ref.watch(statusMessageProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          // Connection status
          Icon(
            isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 14,
            color: isOnline ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? l10n.statusConnected : l10n.statusOffline,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 16),
          // Theme count
          Text(
            l10n.statusThemes(themes.length),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          // Status message
          if (statusMsg.isNotEmpty)
            Flexible(
              child: Text(
                statusMsg,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
