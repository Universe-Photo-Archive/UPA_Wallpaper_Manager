import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../widgets/screen_card.dart';
import '../widgets/status_bar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final screens = ref.watch(screensProvider);
    final themes = ref.watch(themesProvider);
    final config = ref.watch(configProvider);
    final isLoading = ref.watch(isLoadingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // Banner bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerTheme.color ??
                      Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                Image.asset(
                  isDark
                      ? 'assets/images/logo_white.png'
                      : 'assets/images/logo_black.png',
                  height: 30,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Wallpaper Manager',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                Image.asset(
                  'assets/icons/app_icon.png',
                  height: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                // Pause/Resume
                _PauseResumeButton(),
                const SizedBox(width: 8),
                // Lockscreen
                const _LockscreenToggle(),
              ],
            ),
          ),
          // Screen cards
          Expanded(
            child: isLoading && screens.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : screens.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.monitor,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(l10n.statusLoading),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: screens.length,
                        itemBuilder: (context, index) {
                          return ScreenCard(
                            screen: screens[index],
                            themes: themes,
                            screenConfig: config.screens.length > index
                                ? config.screens[index]
                                : null,
                          );
                        },
                      ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}

/// Lockscreen toggle in the top banner. Greys out the switch when the feature
/// can't possibly work on the running machine — i.e. the app is not elevated
/// or Windows is a Home edition (no PersonalizationCSP support). The tooltip
/// then explains exactly which condition is missing.
class _LockscreenToggle extends ConsumerWidget {
  const _LockscreenToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(configProvider);
    final supportAsync = ref.watch(lockscreenSupportProvider);

    final support =
        supportAsync.valueOrNull ?? LockscreenSupport.unknown;
    final probing = supportAsync.isLoading;
    final supported = support.isSupported;

    final theme = Theme.of(context);
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final iconColor =
        supported ? theme.colorScheme.secondary : disabledColor;
    final textColor = supported ? null : disabledColor;

    final tooltip = supported
        ? l10n.lockscreenTooltip
        : _buildUnsupportedTooltip(l10n, support, probing);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(
          l10n.lockscreen,
          style: TextStyle(fontSize: 12, color: textColor),
        ),
        Switch(
          value: supported && config.lockscreenEnabled,
          onChanged: supported
              ? (val) {
                  ref.read(configProvider.notifier).update(
                        (c) => c.copyWith(lockscreenEnabled: val),
                      );
                }
              : null,
        ),
        Tooltip(
          message: tooltip,
          child: Icon(
            supported
                ? Icons.help_outline_rounded
                : Icons.info_outline_rounded,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  String _buildUnsupportedTooltip(
    AppLocalizations l10n,
    LockscreenSupport support,
    bool probing,
  ) {
    if (probing) return l10n.lockscreenTooltip;
    final reasons = <String>[];
    if (!support.isAdmin) reasons.add(l10n.lockscreenReasonAdmin);
    if (!support.isEditionSupported) {
      reasons.add(l10n.lockscreenReasonEdition);
    }
    if (reasons.isEmpty) return l10n.lockscreenTooltip;
    return '${l10n.lockscreenUnsupportedTitle}\n\n• ${reasons.join('\n• ')}';
  }
}

class _PauseResumeButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isPaused = ref.watch(rotationPausedProvider);

    return FilledButton.tonalIcon(
      onPressed: () {
        final rotation = ref.read(rotationServiceProvider);
        final paused = rotation.togglePause();
        ref.read(rotationPausedProvider.notifier).state = paused;
        // Persist the pause state so the slideshow stays paused (or running)
        // across app restarts, like every other user-toggled setting.
        ref
            .read(configProvider.notifier)
            .update((c) => c.copyWith(slideshowPaused: paused));
      },
      icon: Icon(
          isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          size: 16),
      label: Text(isPaused ? l10n.resume : l10n.pause,
          style: const TextStyle(fontSize: 12)),
    );
  }
}
