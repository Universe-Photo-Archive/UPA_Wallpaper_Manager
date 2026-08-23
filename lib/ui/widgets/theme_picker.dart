import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theme_category.dart';

/// Label summarising a theme selection, where an empty set means "all".
String themeSelectionLabel(
  BuildContext context,
  List<ThemeCategory> themes,
  Set<String> selectedNames, {
  required bool emptyMeansAll,
}) {
  final l10n = AppLocalizations.of(context)!;
  if (selectedNames.isEmpty) {
    return emptyMeansAll ? l10n.screenAllThemes : l10n.gallerySelectTheme;
  }
  if (selectedNames.length == themes.length && themes.isNotEmpty) {
    return l10n.screenAllThemes;
  }
  if (selectedNames.length == 1) return selectedNames.first;
  return l10n.galleryThemesSelected(selectedNames.length);
}

/// Opens the checkbox sheet and returns the new selection, or null if the
/// user backed out.
///
/// Ticking the first box selects every theme; the caller decides whether an
/// empty selection means "none yet" (gallery) or "all of them" (a slideshow,
/// which must always have something to show).
Future<Set<String>?> pickThemes({
  required BuildContext context,
  required List<ThemeCategory> themes,
  required Set<String> selected,
  required String Function(ThemeCategory) valueOf,
}) {
  final l10n = AppLocalizations.of(context)!;
  final working = Set<String>.from(selected);

  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final allSelected =
            themes.isNotEmpty && working.length == themes.length;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: allSelected,
                  title: Text(
                    l10n.screenAllThemes,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onChanged: (checked) => setSheetState(() {
                    working
                      ..clear()
                      ..addAll(checked == true
                          ? themes.map(valueOf)
                          : const <String>[]);
                  }),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: themes.length,
                    itemBuilder: (_, index) {
                      final theme = themes[index];
                      final value = valueOf(theme);
                      return CheckboxListTile(
                        value: working.contains(value),
                        title: Text(
                          '${theme.displayName} (${theme.imageCount})',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (checked) => setSheetState(() {
                          if (checked == true) {
                            working.add(value);
                          } else {
                            working.remove(value);
                          }
                        }),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, working),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: Text(l10n.dialogOk),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Form-field flavoured theme picker used by the home cards.
class ThemeCheckboxField extends StatelessWidget {
  final List<ThemeCategory> themes;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const ThemeCheckboxField({
    super.key,
    required this.themes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = themeSelectionLabel(context, themes, selected,
        emptyMeansAll: true);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final result = await pickThemes(
          context: context,
          themes: themes,
          selected: selected,
          valueOf: (t) => t.displayName,
        );
        if (result != null) {
          // Every theme ticked is stored as "none in particular", so a theme
          // added later is picked up automatically.
          onChanged(
            result.length == themes.length ? <String>{} : result,
          );
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(
          children: [
            Icon(
              selected.isEmpty ? Icons.all_inclusive : Icons.collections_outlined,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}
