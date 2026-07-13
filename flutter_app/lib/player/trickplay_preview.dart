import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../models/trickplay_manifest.dart';
import '../ui/ui.dart';

class TrickplayPreview extends StatefulWidget {
  const TrickplayPreview({
    super.key,
    required this.manifest,
    required this.frame,
    required this.apiClient,
  });

  final TrickplayManifest manifest;
  final TrickplayFrame frame;
  final ApiClient apiClient;

  @override
  State<TrickplayPreview> createState() => _TrickplayPreviewState();
}

class _TrickplayPreviewState extends State<TrickplayPreview> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(TrickplayPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame.sheetIndex != widget.frame.sheetIndex ||
        oldWidget.manifest != widget.manifest) {
      _resolve();
    }
  }

  void _resolve() {
    _removeListener();
    _image = null;
    _failed = false;
    final client = widget.apiClient;
    final cookie = client is DioApiClient ? client.cookieHeader : null;
    final provider = NetworkImage(
      widget.manifest.sheetUrl(widget.frame.sheetIndex, client.baseUrl),
      headers: cookie == null ? null : {'Cookie': cookie},
    );
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (image, _) {
        if (mounted) setState(() => _image = image.image);
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  void _removeListener() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (_failed) return const SizedBox.shrink();
    final aspect = widget.manifest.width / widget.manifest.height;
    return Container(
      width: 180,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: aspect,
            child: image == null
                ? const ColoredBox(color: AppColors.surface2)
                : CustomPaint(
                    painter: _SpritePainter(
                      image: image,
                      source: Rect.fromLTWH(
                        widget.frame.sourceX.toDouble(),
                        widget.frame.sourceY.toDouble(),
                        widget.manifest.width.toDouble(),
                        widget.manifest.height.toDouble(),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(_formatTime(widget.frame.time), style: AppTheme.mono),
        ],
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  const _SpritePainter({required this.image, required this.source});

  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      source,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}

String _formatTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
