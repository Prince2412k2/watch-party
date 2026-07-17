import 'package:flutter/material.dart';

import '../palette.dart';
import '../theme.dart';
import '../tokens.dart';
import 'authed_image.dart';
import 'download_ring.dart';

/// A 2:3 poster tile with the [DownloadRing] centered over a flat black-alpha
/// legibility scrim, and a pulsing red "DL" pill top-left while actively
/// downloading. A dark film/tv placeholder fills in when there's no poster.
/// Mirrors `DownloadDetail.tsx`'s `DownloadPoster`.
class DownloadPoster extends StatelessWidget {
  const DownloadPoster({
    super.key,
    this.posterUrl,
    this.kind,
    this.pct = 0,
    this.paused = false,
    this.width,
    this.radius = 14,
    this.ringSize = 78,
  });

  final String? posterUrl;
  final String? kind;
  final double pct;
  final bool paused;

  /// Explicit width; when null the tile expands to its parent's width.
  final double? width;
  final double radius;
  final double ringSize;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    Widget tile = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (posterUrl != null && posterUrl!.isNotEmpty)
              AuthedNetworkImage(
                posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(wp),
              )
            else
              _fallback(wp),
            const ColoredBox(color: Color(0x80000000)),
            Center(
              child: DownloadRing(
                pct: pct,
                size: ringSize,
                color: paused ? wp.dim : wp.text,
              ),
            ),
            if (!paused)
              const Positioned(top: 8, left: 8, child: _LivePill()),
          ],
        ),
      ),
    );
    if (width != null) tile = SizedBox(width: width, child: tile);
    return tile;
  }

  Widget _fallback(WpPalette wp) => ColoredBox(
    color: wp.surface,
    child: Center(
      child: Icon(
        kind == 'movie' ? Icons.movie_outlined : Icons.tv_outlined,
        size: 40,
        color: wp.faint,
      ),
    ),
  );
}

/// The "DL" pill with the pulsing live dot shown while a torrent is active.
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x8C000000),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulseDot(color: AppColors.live, size: 6),
          const SizedBox(width: 5),
          Text(
            'DL',
            style: AppTheme.mono.copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small dot that pulses opacity — the shared "live/active" indicator
/// (`@keyframes pulse` in the web app).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
