import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theme_category.dart';
import '../../models/wallpaper_image.dart';
import '../../providers/app_providers.dart';
import '../../platform/lockscreen_channel.dart';
import '../../platform/media_access_channel.dart';
import '../../platform/wallpaper_channel.dart';
import '../../models/theme_source.dart';
import '../widgets/device_image.dart';
import '../widgets/manage_themes_dialog.dart';
import 'edit_local_theme_screen.dart';
import '../widgets/theme_picker.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  /// Unique keys of the themes whose images are shown. Empty means nothing is
  /// selected yet; several themes can be browsed at once.
  Set<String> _selectedKeys = {};
  bool _loading = false;
  int _loadToken = 0;
  List<WallpaperImage> _images = [];

  /// Set while the user picks photos to take out of a custom theme.
  bool _removing = false;
  final Set<String> _markedForRemoval = {};

  /// The local theme being browsed, when exactly one is selected. Editing only
  /// makes sense then: it is the theme the photos on screen belong to.
  LocalSource? get _editableSource {
    if (_selectedKeys.length != 1) return null;
    final themes = ref.read(themesProvider);
    final index =
        themes.indexWhere((t) => t.uniqueKey == _selectedKeys.first);
    if (index < 0) return null;
    return localSourceFor(ref, themes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themes = ref.watch(themesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Drop selections whose theme was removed in the meantime.
    final available = themes.map((t) => t.uniqueKey).toSet();
    if (_selectedKeys.any((k) => !available.contains(k))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedKeys = _selectedKeys.intersection(available));
        _loadImages();
      });
    }

    // Compact app bar on phones: no logo/title (the dropdown says it all),
    // constrained dropdown width, icon-only "Manage" button.
    final isCompact = MediaQuery.sizeOf(context).width < 640;

    if (_removing) return _buildRemovalScaffold(l10n);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        titleSpacing: isCompact ? 12 : null,
        title: isCompact
            ? null
            : Row(
                children: [
                  Image.asset(
                    isDark
                        ? 'assets/images/logo_white.png'
                        : 'assets/images/logo_black.png',
                    height: 30,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(width: 12),
                  Text(l10n.galleryTitle),
                ],
              ),
        actions: [
          if (themes.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: 8, left: isCompact ? 12 : 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isCompact
                      ? MediaQuery.sizeOf(context).width - 92
                      : 320,
                ),
                child: _ThemeMultiSelect(
                  themes: themes,
                  selected: _selectedKeys,
                  onChanged: (keys) {
                    setState(() => _selectedKeys = keys);
                    _loadImages();
                  },
                ),
              ),
            ),
          if (_editableSource != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: _openThemeEditor,
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: l10n.editTheme,
              ),
            ),
          if (isCompact)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                onPressed: () => ManageThemesDialog.show(context),
                icon: const Icon(Icons.tune_rounded, size: 20),
                tooltip: l10n.manageThemes,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => ManageThemesDialog.show(context),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(l10n.manageThemes),
              ),
            ),
        ],
      ),
      body: _buildGrid(l10n),
    );
  }

  /// Grid of the loaded images, shared by the normal and removal modes.
  Widget _buildGrid(AppLocalizations l10n) {
    return _loading
            ? const Center(child: CircularProgressIndicator())
            : _images.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_outlined,
                              size: 72,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.2)),
                          const SizedBox(height: 20),
                          Text(
                            _selectedKeys.isEmpty
                                ? l10n.gallerySelectThemeHint
                                : l10n.galleryEmpty,
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                            textAlign: TextAlign.center,
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
                          childAspectRatio: 16 / 10,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _images.length,
                        itemBuilder: (context, index) {
                          final image = _images[index];
                          final reference = image.localPath;
                          final marked = reference != null &&
                              _markedForRemoval.contains(reference);
                          return _GalleryTile(
                            image: image,
                            selectable: _removing,
                            selected: marked,
                            onTap: () {
                              if (!_removing) {
                                _showImageDetail(image);
                                return;
                              }
                              if (reference == null) return;
                              setState(() {
                                if (marked) {
                                  _markedForRemoval.remove(reference);
                                } else {
                                  _markedForRemoval.add(reference);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  );
  }

  /// Loads the images of every selected theme, in selection order.
  Future<void> _loadImages() async {
    final selected = ref
        .read(themesProvider)
        .where((t) => _selectedKeys.contains(t.uniqueKey))
        .toList();

    if (selected.isEmpty) {
      setState(() {
        _images = [];
        _loading = false;
      });
      return;
    }

    // Requests are slow enough that the user can change the selection while
    // one is in flight; only the newest one may touch the state.
    final token = ++_loadToken;
    setState(() => _loading = true);

    final images = <WallpaperImage>[];
    for (final theme in selected) {
      try {
        final localSource = localSourceFor(ref, theme);
        if (localSource != null) {
          final localSvc = ref.read(localGalleryServiceProvider);
          images.addAll(await localSvc.getImages(localSource));
        } else {
          final api = ref.read(piwigoApiProvider);
          images.addAll(await api.getThemeImages(
            theme.id,
            baseUrl: theme.sourceBaseUrl,
            recursive: theme.needsRecursiveFetch,
          ));
        }
      } catch (_) {
        // Keep the gallery usable even if one theme fails to load.
      }
      if (!mounted || token != _loadToken) return;
    }

    if (!mounted || token != _loadToken) return;
    setState(() {
      _images = images;
      _loading = false;
    });
  }

  /// Same grid, in "take photos out of the theme" mode.
  Widget _buildRemovalScaffold(AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(() {
            _removing = false;
            _markedForRemoval.clear();
          }),
        ),
        title: Text(l10n.removePhotosTitle),
        actions: [
          TextButton.icon(
            onPressed: _markedForRemoval.isEmpty ? null : _confirmRemoval,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(l10n.removePhotosConfirm(_markedForRemoval.length)),
          ),
        ],
      ),
      body: _buildGrid(l10n),
    );
  }

  Future<void> _openThemeEditor() async {
    final source = _editableSource;
    if (source == null) return;

    final action = await EditLocalThemeScreen.show(context, source: source);
    if (!mounted) return;

    if (action == EditThemeAction.removePhotos) {
      setState(() {
        _removing = true;
        _markedForRemoval.clear();
      });
    }
    // Adding photos or renaming changes the theme, so reload what is shown.
    await _loadImages();
  }

  Future<void> _confirmRemoval() async {
    final l10n = AppLocalizations.of(context)!;
    final source = _editableSource;
    if (source == null) return;

    await ref
        .read(themesManagerProvider)
        .removePhotosFromTheme(source, Set.of(_markedForRemoval));

    if (!mounted) return;
    setState(() {
      _removing = false;
      _markedForRemoval.clear();
    });
    await _loadImages();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.removePhotosDone)),
    );
  }

  void _showImageDetail(WallpaperImage image) {
    showDialog(
      context: context,
      builder: (ctx) => _ImageDetailDialog(image: image),
    );
  }
}

/// Theme picker of the gallery: several themes can be browsed at once.
class _ThemeMultiSelect extends StatelessWidget {
  final List<ThemeCategory> themes;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _ThemeMultiSelect({
    required this.themes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The gallery stores unique keys, but the label reads better with names.
    final names = themes
        .where((t) => selected.contains(t.uniqueKey))
        .map((t) => t.displayName)
        .toSet();
    final label =
        themeSelectionLabel(context, themes, names, emptyMeansAll: false);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final result = await pickThemes(
          context: context,
          themes: themes,
          selected: selected,
          valueOf: (t) => t.uniqueKey,
        );
        if (result != null) onChanged(result);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final WallpaperImage image;
  final VoidCallback onTap;

  /// True while the user is picking photos to take out of a theme.
  final bool selectable;
  final bool selected;

  const _GalleryTile({
    required this.image,
    required this.onTap,
    this.selectable = false,
    this.selected = false,
  });

  /// A local image is either a cached file or one of the user's own photos,
  /// the latter referenced in place and only renderable through a thumbnail.
  bool get _isLocal {
    final path = image.localPath;
    if (path == null) return false;
    return MediaAccessChannel.isDocumentUri(path) || File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _isLocal
                ? DeviceImageView(
                    reference: image.localPath!,
                    maxSize: 500,
                  )
                : Image.network(
                    image.mediumUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Text(
                  image.filename,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (selectable)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.15),
                  border: selected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        )
                      : null,
                ),
              ),
            if (selectable)
              Positioned(
                top: 6,
                left: 6,
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
            if (image.isDownloaded && !selectable)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.download_done,
                      size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageDetailDialog extends ConsumerWidget {
  final WallpaperImage image;

  const _ImageDetailDialog({required this.image});

  bool get _isLocal {
    final path = image.localPath;
    if (path == null) return false;
    return MediaAccessChannel.isDocumentUri(path) || File(path).existsSync();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final screens = ref.watch(screensProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _isLocal
                  ? DeviceImageView(
                      reference: image.localPath!,
                      maxSize: 1600,
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      image.fullSizeUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox(
                          height: 300,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (!Platform.isIOS) ...[
                    Text(l10n.gallerySetAs,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 10),
                    // A phone has a single screen but two wallpaper slots
                    // (home + lock); a desktop has one slot per monitor.
                    if (Platform.isAndroid)
                      Column(
                        children: [
                          // Applying to both slots is the most common choice,
                          // so it leads.
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _setAsBoth(ref, context),
                              icon: const Icon(Icons.done_all_rounded,
                                  size: 16),
                              label: Text(l10n.galleryTargetBoth),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _setAsWallpaper(ref, context, 0),
                              icon: const Icon(Icons.wallpaper_rounded,
                                  size: 16),
                              label: Text(l10n.galleryTargetWallpaper),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _setAsLockscreen(ref, context),
                              icon: const Icon(Icons.lock_outline_rounded,
                                  size: 16),
                              label: Text(l10n.galleryTargetLockscreen),
                            ),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ...screens.map((screen) => ElevatedButton.icon(
                                onPressed: () =>
                                    _setAsWallpaper(ref, context, screen.id),
                                icon: const Icon(Icons.monitor, size: 16),
                                label: Text(
                                    '${l10n.screenName(screen.id + 1)}${screen.isPrimary ? " (${l10n.screenPrimary})" : ""}'),
                              )),
                          if (screens.length > 1)
                            OutlinedButton.icon(
                              onPressed: () => _setAsWallpaperAll(
                                  ref, context, screens.length),
                              icon: const Icon(Icons.desktop_windows, size: 16),
                              label: Text(l10n.galleryAllScreens),
                            ),
                        ],
                      ),
                  ],
                  if (Platform.isIOS)
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.save_alt_rounded),
                      label: Text(l10n.gallerySaveToDevice),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.dialogCancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _resolveLocalPath(WidgetRef ref) async {
    if (_isLocal) return image.localPath;
    final cache = ref.read(cacheServiceProvider);
    return cache.downloadImage('manual', image);
  }

  Future<void> _setAsWallpaper(
      WidgetRef ref, BuildContext context, int screenId) async {
    final l10n = AppLocalizations.of(context)!;
    final path = await _resolveLocalPath(ref);
    if (path != null && context.mounted) {
      final success = await WallpaperChannel.setWallpaper(
          imagePath: path, screenId: screenId);

      if (success) {
        final current = Map<int, String>.from(
            ref.read(currentWallpapersProvider));
        current[screenId] = path;
        ref.read(currentWallpapersProvider.notifier).state = current;
      }

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? l10n.galleryWallpaperApplied
                : l10n.galleryWallpaperFailed),
          ),
        );
      }
    }
  }

  /// Applies the image to the home wallpaper and the lock screen at once.
  Future<void> _setAsBoth(WidgetRef ref, BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final path = await _resolveLocalPath(ref);
    if (path == null || !context.mounted) return;

    final success = await WallpaperChannel.setBothWallpapers(path);
    if (success) {
      final current =
          Map<int, String>.from(ref.read(currentWallpapersProvider));
      current[0] = path;
      current[1] = path;
      ref.read(currentWallpapersProvider.notifier).state = current;
    }
    if (!context.mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            success ? l10n.galleryBothApplied : l10n.galleryWallpaperFailed),
      ),
    );
  }

  Future<void> _setAsLockscreen(WidgetRef ref, BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final path = await _resolveLocalPath(ref);
    if (path == null || !context.mounted) return;

    final success = await LockscreenChannel.setLockscreen(path);
    if (!context.mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? l10n.galleryLockscreenApplied
            : l10n.galleryWallpaperFailed),
      ),
    );
  }

  Future<void> _setAsWallpaperAll(
      WidgetRef ref, BuildContext context, int screenCount) async {
    final l10n = AppLocalizations.of(context)!;
    final path = await _resolveLocalPath(ref);
    if (path != null && context.mounted) {
      bool anySuccess = false;
      final current =
          Map<int, String>.from(ref.read(currentWallpapersProvider));
      for (int i = 0; i < screenCount; i++) {
        final success =
            await WallpaperChannel.setWallpaper(imagePath: path, screenId: i);
        if (success) {
          anySuccess = true;
          current[i] = path;
        }
      }
      ref.read(currentWallpapersProvider.notifier).state = current;

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(anySuccess
                ? l10n.galleryWallpaperAppliedAll
                : l10n.galleryWallpaperFailed),
          ),
        );
      }
    }
  }
}
