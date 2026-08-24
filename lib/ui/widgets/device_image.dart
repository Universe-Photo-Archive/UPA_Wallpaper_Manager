import 'dart:io';
import 'package:flutter/material.dart';
import '../../platform/media_access_channel.dart';

/// Displays an image whether it is a plain file or one of the user's photos
/// referenced through Android's document system.
///
/// Flutter cannot render a `content://` URI, and the originals are read in
/// place rather than copied, so the platform is asked for a small cached JPEG
/// standing in for the photo. Those thumbnails weigh tens of kilobytes each,
/// against several megabytes for a full photo.
class DeviceImageView extends StatefulWidget {
  final String reference;
  final int maxSize;
  final BoxFit fit;

  /// Keeps the previous frame while the next one decodes, so a rotation never
  /// flashes an empty box.
  final bool gaplessPlayback;

  const DeviceImageView({
    super.key,
    required this.reference,
    this.maxSize = 500,
    this.fit = BoxFit.cover,
    this.gaplessPlayback = false,
  });

  @override
  State<DeviceImageView> createState() => _DeviceImageViewState();
}

class _DeviceImageViewState extends State<DeviceImageView> {
  static final Map<String, String> _thumbnails = {};

  String? _path;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant DeviceImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.maxSize != widget.maxSize) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (!MediaAccessChannel.isDocumentUri(widget.reference)) {
      setState(() {
        _path = widget.reference;
        _failed = false;
      });
      return;
    }

    final key = '${widget.reference}#${widget.maxSize}';
    final cached = _thumbnails[key];
    if (cached != null) {
      setState(() {
        _path = cached;
        _failed = false;
      });
      return;
    }

    setState(() {
      _path = null;
      _failed = false;
    });

    final generated = await MediaAccessChannel.thumbnail(
      widget.reference,
      maxSize: widget.maxSize,
    );
    if (!mounted) return;
    if (generated == null) {
      setState(() => _failed = true);
      return;
    }
    _thumbnails[key] = generated;
    setState(() => _path = generated);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _Unavailable();
    final path = _path;
    if (path == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }

    return Image.file(
      File(path),
      fit: widget.fit,
      gaplessPlayback: widget.gaplessPlayback,
      cacheWidth: widget.maxSize * 2,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const _Unavailable(),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    );
  }
}
