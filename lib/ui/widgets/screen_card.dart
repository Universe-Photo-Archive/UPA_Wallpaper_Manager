import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_config.dart';
import '../../models/screen_info.dart';
import '../../models/theme_category.dart';
import '../../providers/app_providers.dart';

class ScreenCard extends ConsumerStatefulWidget {
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
  ConsumerState<ScreenCard> createState() => _ScreenCardState();
}

class _ScreenCardState extends ConsumerState<ScreenCard> {
  late final TextEditingController _delayController;
  final FocusNode _delayFocus = FocusNode();

  /// The slideshow service honours the exact delay, but below a minute the
  /// rotation is pointless and drains the battery.
  static const int _androidMinMinutes = 1;

  bool get _isMobile => Platform.isAndroid;

  int get _minDelayFor {
    if (!_isMobile) return 1;
    final unit = widget.screenConfig?.rotationDelayUnit ?? 'minutes';
    return unit == 'minutes' ? _androidMinMinutes : 1;
  }

  @override
  void initState() {
    super.initState();
    _delayController = TextEditingController(
      text: (widget.screenConfig?.rotationDelay ?? 15).toString(),
    );
    // Snap a too-short value back to the minimum once the field loses focus,
    // so the user can still type freely while editing.
    _delayFocus.addListener(() {
      if (_delayFocus.hasFocus) return;
      final min = _minDelayFor;
      final value = int.tryParse(_delayController.text) ?? min;
      if (value < min) {
        _delayController.text = min.toString();
        _updateScreenConfig(ref, widget.screen.id, rotationDelay: min);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ScreenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.screenConfig?.rotationDelay ?? 15;
    final prev = oldWidget.screenConfig?.rotationDelay ?? 15;
    // Only rewrite the field when the stored value actually changed from
    // outside (e.g. config reload). Never clobber the user's in-progress
    // typing on wallpaper-preview rebuilds.
    if (next != prev && _delayController.text != next.toString()) {
      _delayController.text = next.toString();
    }
  }

  @override
  void dispose() {
    _delayFocus.dispose();
    _delayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screen = widget.screen;
    final themes = widget.themes;
    final screenConfig = widget.screenConfig;
    final wallpapers = ref.watch(currentWallpapersProvider);
    final currentPath = wallpapers[screen.id];

    final selectedTheme = screenConfig?.themeName ?? 'all';
    final rotationEnabled = screenConfig?.rotationEnabled ?? true;
    var delayUnit = screenConfig?.rotationDelayUnit ?? 'minutes';
    // A config saved on desktop (or by an older build) may use seconds, which
    // mobile no longer offers — fall back so the dropdown keeps a valid value.
    if (_isMobile && delayUnit == 'seconds') delayUnit = 'minutes';

    final unitLabels = {
      // The slideshow service works in minutes; seconds would only burn
      // battery for a change nobody sees.
      if (!_isMobile) 'seconds': l10n.timeSeconds,
      'minutes': l10n.timeMinutes,
      'hours': l10n.timeHours,
    };

    // On Android the two "screens" are the home wallpaper and the lock
    // screen; each gets a coloured title so the cards cannot be confused.
    final isLockTarget = _isMobile && screen.id == 1;
    final targetColor = isLockTarget
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, constraints) {
          // On phones (and narrow windows) the side-by-side desktop layout
          // does not fit: stack the preview above the settings instead, and
          // drop the multi-monitor chrome ("Screen 1", "Primary",
          // resolution) that is meaningless on a single-screen device.
          final narrow = constraints.maxWidth < 520;

          Widget previewImage() => currentPath != null
              ? Image.file(
                  File(currentPath),
                  fit: BoxFit.cover,
                  // Keep showing the previous wallpaper while the new one
                  // decodes, so rotations never flash a blank frame.
                  gaplessPlayback: true,
                  // Decode at preview size instead of full 4K+: much faster
                  // and lighter on memory.
                  cacheWidth: narrow ? 900 : 520,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => _Placeholder(),
                )
              : _Placeholder();

          final preview = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: narrow
                    ? AspectRatio(aspectRatio: 16 / 9, child: previewImage())
                    : SizedBox(width: 260, height: 146, child: previewImage()),
              ),
              // Ban the photo on screen right now: it disappears from both
              // slots and another one takes its place immediately.
              if (currentPath != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _excludeCurrent(context, screen.id),
                  icon: const Icon(Icons.block_outlined, size: 16),
                  label: Text(
                    l10n.excludeImage,
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          );

          // Header: screen name + badges + rotation toggle (desktop), or
          // the target title and its toggle (mobile).
          final header = Row(
            children: [
              if (_isMobile) ...[
                Icon(
                  isLockTarget
                      ? Icons.lock_outline_rounded
                      : Icons.wallpaper_rounded,
                  size: 18,
                  color: targetColor,
                ),
                const SizedBox(width: 8),
                // The label states what the switch next to it does; it wraps
                // rather than running under the switch.
                Expanded(
                  child: Text(
                    isLockTarget ? l10n.targetLockscreen : l10n.targetWallpaper,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: targetColor,
                    ),
                  ),
                ),
              ],
              if (!narrow) ...[
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
                Flexible(
                  child: Text(screen.resolution,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4))),
                ),
                const Spacer(),
              ],
              // The coloured title already says which slot this is; on mobile
              // the switch speaks for itself.
              if (!_isMobile)
                Flexible(
                  child: Text(l10n.screenRotationEnabled,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6))),
                ),
              if (narrow && !_isMobile) const Spacer(),
              const SizedBox(width: 6),
              Switch(
                value: rotationEnabled,
                onChanged: (val) => _updateScreenConfig(
                  ref, screen.id,
                  rotationEnabled: val,
                ),
              ),
            ],
          );

          final settings = Column(
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
                              controller: _delayController,
                              focusNode: _delayFocus,
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
                                if (d != null && d >= _minDelayFor) {
                                  _updateScreenConfig(ref, screen.id,
                                      rotationDelay: d);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: DropdownButton<String>(
                              value: delayUnit,
                              isExpanded: true,
                              underline: const SizedBox(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface),
                              items: unitLabels.entries
                                  .map((e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value,
                                            overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (unit) {
                                if (unit == null) return;
                                // Switching to minutes on mobile must respect
                                // the background job's 15-minute floor.
                                final current =
                                    int.tryParse(_delayController.text) ?? 15;
                                final min = (_isMobile && unit == 'minutes')
                                    ? _androidMinMinutes
                                    : 1;
                                if (current < min) {
                                  _delayController.text = min.toString();
                                }
                                _updateScreenConfig(
                                  ref,
                                  screen.id,
                                  rotationDelayUnit: unit,
                                  rotationDelay:
                                      current < min ? min : null,
                                );
                              },
                            ),
                          ),
                  ],
                ),
                if (_isMobile) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.rotationDelayMobileHint,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ]);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 14),
              if (narrow) ...[
                preview,
                const SizedBox(height: 14),
                settings,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview,
                    const SizedBox(width: 20),
                    Expanded(child: settings),
                  ],
                ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _excludeCurrent(BuildContext context, int screenId) async {
    final l10n = AppLocalizations.of(context)!;
    final excluded = await ref.read(exclusionsProvider).excludeCurrent(screenId);
    if (!context.mounted || !excluded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.excludeImageDone)),
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
        // Replace (never mutate) the entry: the old instance stays part of
        // the previous state so listeners can diff prev vs next reliably.
        screens[idx] = screens[idx].copyWith(
          themeName: themeName,
          rotationEnabled: rotationEnabled,
          rotationDelay: rotationDelay,
          rotationDelayUnit: rotationDelayUnit,
        );
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
