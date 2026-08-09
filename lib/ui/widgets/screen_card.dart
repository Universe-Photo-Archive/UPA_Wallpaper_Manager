import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_config.dart';
import '../../models/screen_info.dart';
import '../../models/theme_category.dart';
import '../../providers/app_providers.dart';

class ScreenCard extends ConsumerWidget {
  final ScreenInfo screen;
  final List<ThemeCategory> themes;
  final ScreenConfig? screenConfig;

  const ScreenCard({
    super.key,
    required this.screen,
    required this.themes,
    this.screenConfig,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final wallpapers = ref.watch(currentWallpapersProvider);
    final currentPath = wallpapers[screen.id];

    final selectedTheme = screenConfig?.themeName ?? 'all';
    final rotationEnabled = screenConfig?.rotationEnabled ?? true;
    final delay = screenConfig?.rotationDelay ?? 15;
    final delayUnit = screenConfig?.rotationDelayUnit ?? 'minutes';

    final unitLabels = {
      'seconds': l10n.timeSeconds,
      'minutes': l10n.timeMinutes,
      'hours': l10n.timeHours,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: screen name + badges + rotation toggle
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monitor,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        l10n.screenName(screen.id + 1),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (screen.isPrimary) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(l10n.screenPrimary,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color:
                                Theme.of(context).colorScheme.secondary)),
                  ),
                ],
                const SizedBox(width: 10),
                Text(screen.resolution,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4))),
                const Spacer(),
                Text(l10n.screenRotationEnabled,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(width: 6),
                Switch(
                  value: rotationEnabled,
                  onChanged: (val) => _updateScreenConfig(
                    ref, screen.id,
                    rotationEnabled: val,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Body: preview + config
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 260,
                    height: 146,
                    child: currentPath != null
                        ? Image.file(
                            File(currentPath),
                            fit: BoxFit.cover,
                            // Keep showing the previous wallpaper while the
                            // new one decodes, so rotations never flash a
                            // blank frame.
                            gaplessPlayback: true,
                            // Decode at preview size instead of full 4K+:
                            // much faster and lighter on memory (520 px
                            // covers the 260 px box on high-DPI screens).
                            cacheWidth: 520,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => _Placeholder(),
                          )
                        : _Placeholder(),
                  ),
                ),
                const SizedBox(width: 20),
                // Config
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Theme selector
                      Text(l10n.screenTheme,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7))),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 44,
                        child: DropdownButtonFormField<String>(
                          initialValue: themes
                                  .any((t) => t.displayName == selectedTheme)
                              ? selectedTheme
                              : 'all',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Row(
                                children: [
                                  const Icon(Icons.all_inclusive, size: 16),
                                  const SizedBox(width: 8),
                                  Text(l10n.screenAllThemes,
                                      style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            ),
                            ...themes.map((t) => DropdownMenuItem(
                                  value: t.displayName,
                                  child: Text(
                                    '${t.displayName} (${t.imageCount})',
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              _updateScreenConfig(ref, screen.id,
                                  themeName: val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Delay
                      Text(l10n.rotationDelay,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7))),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            height: 40,
                            child: TextField(
                              controller: TextEditingController(
                                  text: delay.toString()),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                              ),
                              onChanged: (value) {
                                final d = int.tryParse(value);
                                if (d != null && d > 0) {
                                  _updateScreenConfig(ref, screen.id,
                                      rotationDelay: d);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: delayUnit,
                            underline: const SizedBox(),
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface),
                            items: unitLabels.entries
                                .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value),
                                    ))
                                .toList(),
                            onChanged: (unit) {
                              if (unit != null) {
                                _updateScreenConfig(ref, screen.id,
                                    rotationDelayUnit: unit);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateScreenConfig(
    WidgetRef ref,
    int screenId, {
    String? themeName,
    bool? rotationEnabled,
    int? rotationDelay,
    String? rotationDelayUnit,
  }) {
    ref.read(configProvider.notifier).update((config) {
      final screens = List<ScreenConfig>.from(config.screens);
      final idx = screens.indexWhere((s) => s.screenId == screenId);
      if (idx >= 0) {
        if (themeName != null) screens[idx].themeName = themeName;
        if (rotationEnabled != null) {
          screens[idx].rotationEnabled = rotationEnabled;
        }
        if (rotationDelay != null) {
          screens[idx].rotationDelay = rotationDelay;
        }
        if (rotationDelayUnit != null) {
          screens[idx].rotationDelayUnit = rotationDelayUnit;
        }
      } else {
        screens.add(ScreenConfig(
          screenId: screenId,
          themeName: themeName ?? 'all',
          rotationEnabled: rotationEnabled ?? true,
          rotationDelay: rotationDelay ?? 15,
          rotationDelayUnit: rotationDelayUnit ?? 'minutes',
        ));
      }
      return config.copyWith(screens: screens);
    });
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.image_outlined,
            size: 40,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.15)),
      ),
    );
  }
}
