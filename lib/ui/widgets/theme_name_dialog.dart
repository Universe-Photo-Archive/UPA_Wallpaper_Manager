import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Asks for the name of a local theme. Returns null if the user cancels.
///
/// Confirming an empty name keeps the dialog open and says a name is needed:
/// closing it without a word looked exactly like the tap having been missed.
Future<String?> promptThemeName(
  BuildContext context, {
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  var missingName = false;

  final name = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty) {
              setDialogState(() => missingName = true);
              return;
            }
            Navigator.pop(ctx, value);
          }

          return AlertDialog(
            title: Text(l10n.themeNameTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.themeNameLabel,
                border: const OutlineInputBorder(),
                errorText: missingName ? l10n.themeNameRequired : null,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (missingName) setDialogState(() => missingName = false);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.dialogCancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.dialogOk)),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  return name;
}
