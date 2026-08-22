import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theme_category.dart';
import '../../models/theme_source.dart';
import '../../models/wallpaper_image.dart';
import '../../providers/app_providers.dart';
import '../../platform/lockscreen_channel.dart';
import '../../platform/wallpaper_channel.dart';
import '../widgets/manage_themes_dialog.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  ThemeCategory? _selectedTheme;
  bool _loading = false;
  List<WallpaperImage> _images = [];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themes = ref.watch(themesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If the previously selected theme was removed, reset selection.
    if (_selectedTheme != null &&
        !themes.any((t) => t.uniqueKey == _selectedTheme!.uniqueKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedTheme = null;
          _images = [];
        });
      });
    }

    // Compact app bar on phones: no logo/title (the dropdown says it all),
    // constrained dropdown width, icon-only "Manage" button.
    final isCompact = MediaQuery.sizeOf(context).width < 640;

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
                child: DropdownButton<String?>(
                  value: _selectedTheme?.uniqueKey,
                  hint: Text(l10n.screenAllThemes),
                  underline: const SizedBox(),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.screenAllThemes,
                          overflow: TextOverflow.ellipsis),
                    ),
                    ...themes.map((t) => DropdownMenuItem<String?>(
                          value: t.uniqueKey,
                          child: Text('${t.displayName} (${t.imageCount})',
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (key) {
                    setState(() {
                      _selectedTheme = key == null
                          ? null
                          : themes.firstWhere((t) => t.uniqueKey == key);
                    });
                    _loadImages();
                  },
                ),
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
      body: _loading
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
                          _selectedTheme == null
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
                        return _GalleryTile(
                          image: _images[index],
                          onTap: () => _showImageDetail(_images[index]),
                        );
                      },
                    );
                  },
                ),
    );
  }

  Future<void> _loadImages() async {
    final theme = _selectedTheme;
    if (theme == null) {
      setState(() {
        _images = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    List<WallpaperImage> images = [];
    try {
      if (theme.sourceBaseUrl.startsWith(LocalSource.urlScheme)) {
        final folderPath =
            theme.sourceBaseUrl.substring(LocalSource.urlScheme.length);
        final localSvc = ref.read(localGalleryServiceProvider);
        images = await localSvc.getImages(LocalSource(
          folderPath: folderPath,
          name: theme.nameRaw,
          id: theme.id,
          recursive: true,
        ));
      } else {
        final api = ref.read(piwigoApiProvider);
        images = await api.getThemeImages(
          theme.id,
          baseUrl: theme.sourceBaseUrl,
          recursive: theme.needsRecursiveFetch,
        );
      }
    } catch (_) {
      // Keep the gallery usable even if a local folder scan fails;
      // Piwigo errors are already handled inside getThemeImages.
      images = [];
    }

    if (!mounted) return;
    // The user may have switched theme while this request was in flight —
    // ignore stale results, the newer request will update the state.
    if (_selectedTheme?.uniqueKey != theme.uniqueKey) return;

    setState(() {
      _images = images;
      _loading = false;
    });
  }

  void _showImageDetail(WallpaperImage image) {
    showDialog(
      context: context,
      builder: (ctx) => _ImageDetailDialog(image: image),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final WallpaperImage image;
  final VoidCallback onTap;

  const _GalleryTile({required this.image, required this.onTap});

  bool get _isLocal =>
      image.localPath != null && File(image.localPath!).existsSync();

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
                ? Image.file(
                    File(image.localPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
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
            if (image.isDownloaded)
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

  bool get _isLocal =>
      image.localPath != null && File(image.localPath!).existsSync();

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
                  ? Image.file(
                      File(image.localPath!),
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
