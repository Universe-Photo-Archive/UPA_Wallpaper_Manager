import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Asks for the name of a local theme. Returns null if the user cancels.
Future<String?> promptThemeName(
  BuildContext context, {
  required String initial,
}) {
  final controller = TextEditingController(text: initial);

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return AlertDialog(
        title: Text(l10n.themeNameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.themeNameLabel,
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.dialogOk),
          ),
        ],
      );
    },
  ).then((value) => (value == null || value.isEmpty) ? null : value);
}
