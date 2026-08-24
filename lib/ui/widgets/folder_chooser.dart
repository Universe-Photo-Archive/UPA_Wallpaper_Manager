import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/media_access_channel.dart';

/// Asks the user for a folder holding their photos.
///
/// On Android this goes through the system document picker and takes a lasting
/// grant on the folder, which is what lets the app read those photos later
/// without copying them and without any storage permission. Elsewhere a plain
/// directory path is enough.
Future<String?> chooseFolder(BuildContext context) async {
  if (Platform.isAndroid) return MediaAccessChannel.pickFolder();

  try {
    return await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppLocalizations.of(context)!.manageThemesLocalPickFolder,
    );
  } catch (_) {
    return null;
  }
}
