import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../platform/media_access_channel.dart';
import 'device_image.dart';

/// Grid of the photos held by a folder, for the user to tick the ones they
/// want in a theme.
///
/// Selecting inside a folder rather than through a plain photo picker is what
/// makes a custom theme durable: the folder grant taken beforehand lets the
/// app — and the background slideshow — read those photos later, so none of
/// them has to be copied.
class LocalPhotoPicker extends StatefulWidget {
  final String root;
  final Set<String> alreadyIn;

  const LocalPhotoPicker({
    super.key,
    required this.root,
    this.alreadyIn = const {},
  });

  /// Returns the chosen references, or null if the user backed out.
  static Future<List<String>?> show(
    BuildContext context, {
    required String root,
    Set<String> alreadyIn = const {},
  }) {
    return Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => LocalPhotoPicker(root: root, alreadyIn: alreadyIn),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<LocalPhotoPicker> createState() => _LocalPhotoPickerState();
}

class _LocalPhotoPickerState extends State<LocalPhotoPicker> {
  List<String> _references = [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final references = <String>[];
    if (MediaAccessChannel.isDocumentUri(widget.root)) {
      references.addAll(
        (await MediaAccessChannel.listFolderImages(widget.root))
            .map((image) => image.uri),
      );
    } else {
      references.addAll(await _scanDesktopFolder(widget.root));
    }

    if (!mounted) return;
    setState(() {
      // Photos already in the theme are listed but cannot be ticked twice.
      _references =
          references.where((r) => !widget.alreadyIn.contains(r)).toList();
      _loading = false;
    });
  }

  Future<List<String>> _scanDesktopFolder(String path) async {
    const extensions = {
      '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif', '.tif', '.tiff'
    };
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final files = <File>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File &&
            extensions.contains(p.extension(entity.path).toLowerCase())) {
          files.add(entity);
        }
      }
    } catch (_) {}
    files.sort((a, b) =>
        p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
    return files.map((f) => f.path).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pickPhotosTitle),
        actions: [
          if (_references.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _references.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(_references);
                }
              }),
              child: Text(_selected.length == _references.length
                  ? l10n.pickPhotosNone
                  : l10n.pickPhotosAll),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _references.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.manageThemesNoImagesInFolder,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                )
              : LayoutBuilder(builder: (context, constraints) {
                  final crossCount = constraints.maxWidth > 1200
                      ? 6
                      : constraints.maxWidth > 900
                          ? 5
                          : constraints.maxWidth > 600
                              ? 4
                              : 3;
                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _references.length,
                    itemBuilder: (context, index) {
                      final reference = _references[index];
                      final selected = _selected.contains(reference);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (selected) {
                            _selected.remove(reference);
                          } else {
                            _selected.add(reference);
                          }
                        }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: DeviceImageView(
                                reference: reference,
                                maxSize: 300,
                              ),
                            ),
                            if (selected)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.35),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white70,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
      bottomNavigationBar: _references.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.toList()),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(l10n.pickPhotosConfirm(_selected.length)),
                ),
              ),
            ),
    );
  }
}
