import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/download_poster.dart';
import '../../ui/widgets/download_ring.dart';

/// Full-screen download detail overlay (mirrors `components/DownloadDetail.tsx`):
/// a blurred-poster hero + scrims, back chevron, poster with ring, a
/// DOWNLOADING / PAUSED / FINISHING UP status pill, big title + subtitle,
/// rating + genres, mono info line, a large ring + a mono stats grid (↓ speed /
/// ETA / Seeds / Peers / size), Pause/Resume + Delete, and the overview. The
/// live torrent is re-read from the shared 4s poll so the ring + stats update in
/// place; rich metadata comes from `GET /api/servarr/downloads/:hash/detail`,
/// falling back to the enriched fields. Pushed on the root navigator so it
/// covers the shell chrome.
class DownloadDetailScreen extends ConsumerStatefulWidget {
  const DownloadDetailScreen({super.key, required this.hash});
  final String hash;

  @override
  ConsumerState<DownloadDetailScreen> createState() =>
      _DownloadDetailScreenState();
}

class _DownloadDetailScreenState extends ConsumerState<DownloadDetailScreen> {
  bool _busy = false;
  bool _sawTorrent = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final snap = ref.watch(servarrDownloadsPollProvider).valueOrNull;
    final torrent = snap?.list.cast<ServarrDownload?>().firstWhere(
          (t) => t?.hash == widget.hash,
          orElse: () => null,
        );

    if (torrent == null) {
      // The download finished + left the queue (or was removed) → close.
      if (_sawTorrent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return Scaffold(
        backgroundColor: wp.bg,
        body: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    _sawTorrent = true;

    final detail = ref.watch(servarrDownloadDetailProvider(widget.hash)).valueOrNull;
    final pct = torrent.percent;
    final paused = torrent.isPaused;
    final done = pct >= 100;

    final kind = detail?.kind ?? torrent.kind;
    final title = (detail?.title?.isNotEmpty == true ? detail!.title! : torrent.name);
    final subtitle = detail?.subtitle ?? torrent.subtitle;
    final posterUrl = detail?.posterUrl ?? torrent.posterUrl;
    final overview = detail?.overview;
    final genres = detail?.genres ?? const <String>[];
    final rating = detail?.rating;
    final runtime = fmtRuntimeFromMinutes(detail?.runtime);
    final infoLine = <String>[
      if (detail?.year != null) detail!.year!,
      if (runtime != null) runtime,
      if (detail?.certification != null && detail!.certification!.isNotEmpty)
        detail.certification!,
      if (detail?.network != null && detail!.network!.isNotEmpty) detail.network!,
      if (detail?.status != null && detail!.status!.isNotEmpty) detail.status!,
    ];

    return Scaffold(
      backgroundColor: wp.bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Positioned.fill(child: _Hero(posterUrl: posterUrl)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 90, 40, 40),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 200,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusLg),
                              boxShadow: wp.cardShadow,
                            ),
                            child: DownloadPoster(
                              posterUrl: posterUrl,
                              kind: kind,
                              pct: pct.toDouble(),
                              paused: paused,
                              width: 200,
                              radius: AppSpacing.radiusLg,
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _StatusPill(
                                  label: done
                                      ? 'FINISHING UP'
                                      : paused
                                          ? 'PAUSED'
                                          : 'DOWNLOADING',
                                  paused: paused,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.headlineLarge
                                      .copyWith(color: wp.text),
                                ),
                                if (subtitle != null && subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(subtitle,
                                      style: AppTheme.mono.copyWith(
                                          fontSize: 13.5, color: wp.dim)),
                                ],
                                if (rating != null || genres.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  _RatingGenres(rating: rating, genres: genres),
                                ],
                                if (infoLine.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      for (final v in infoLine)
                                        Text(v,
                                            style: AppTheme.mono.copyWith(
                                                fontSize: 13, color: wp.dim)),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 22),
                                _StatsRow(torrent: torrent, done: done, paused: paused),
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    AppButton(
                                      label: paused ? 'Resume' : 'Pause',
                                      icon: paused ? Icons.play_arrow : Icons.pause,
                                      variant: AppButtonVariant.primary,
                                      onPressed: (_busy || done)
                                          ? null
                                          : _pauseResume,
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    AppButton(
                                      label: 'Delete',
                                      icon: Icons.delete_outline,
                                      variant: AppButtonVariant.danger,
                                      onPressed: _busy ? null : () => _delete(title),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (overview != null && overview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 80),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        overview,
                        style: TextStyle(fontSize: 15, height: 1.65, color: wp.dim),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 60),
              ],
            ),
          ),
          Positioned(
            top: 18,
            left: 18,
            child: _BackChevron(onTap: () => Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }

  Future<void> _pauseResume() async {
    final actions = ref.read(servarrQueueActionsProvider);
    final t = ref.read(servarrDownloadsPollProvider).valueOrNull?.list.firstWhere(
          (t) => t.hash == widget.hash,
          orElse: () => ServarrDownload({'hash': widget.hash}),
        );
    if (t == null) return;
    setState(() => _busy = true);
    if (t.isPaused) {
      await actions.resume(widget.hash);
    } else {
      await actions.pause(widget.hash);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(String name) async {
    final deleteFiles = await showDownloadDeleteDialog(context, name: name);
    if (deleteFiles == null || !mounted) return;
    setState(() => _busy = true);
    await ref
        .read(servarrQueueActionsProvider)
        .deleteTorrent(widget.hash, deleteFiles: deleteFiles);
    if (mounted) Navigator.of(context).maybePop();
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.torrent, required this.done, required this.paused});
  final ServarrDownload torrent;
  final bool done;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    Widget stat(String text, {bool faint = false}) => Text(
          text,
          style: AppTheme.mono.copyWith(
            fontSize: 13,
            color: faint ? wp.faint : wp.dim,
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DownloadRing(
          pct: torrent.percent.toDouble(),
          size: 104,
          stroke: 8,
          color: paused ? wp.dim : wp.text,
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                stat('↓ ${fmtSpeed(torrent.dlspeed)}'),
                stat('ETA ${done ? '—' : fmtEta(torrent.eta)}'),
                stat('Seeds ${torrent.numSeeds}'),
                stat('Peers ${torrent.numLeechs}'),
                stat(fmtSize(torrent.size), faint: true),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.paused});
  final String label;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        paused
            ? Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: wp.faint, shape: BoxShape.circle),
              )
            : const PulseDot(color: AppColors.live, size: 7),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.mono.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: wp.dim,
          ),
        ),
      ],
    );
  }
}

class _RatingGenres extends StatelessWidget {
  const _RatingGenres({required this.rating, required this.genres});
  final double? rating;
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, size: 16, color: wp.text),
              const SizedBox(width: 5),
              Text(rating!.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: wp.text)),
            ],
          ),
        for (final g in genres.take(3))
          Text(g,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: wp.dim)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.posterUrl});
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrl != null && posterUrl!.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0x66000000),
                BlendMode.darken,
              ),
              child: AuthedNetworkImage(
                posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: wp.surface),
              ),
            ),
          )
        else
          ColoredBox(color: wp.surface),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                wp.bg,
                wp.bg.withValues(alpha: 0.55),
                wp.bg.withValues(alpha: 0.3),
              ],
              stops: const [0.04, 0.48, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xB8000000), Color(0x59000000), Color(0x00000000)],
              stops: [0.0, 0.45, 0.82],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackChevron extends StatelessWidget {
  const _BackChevron({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141416),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.chevron_left, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Delete-confirm modal with an "Also delete downloaded files" toggle (default
/// OFF, matching the web). Returns the toggle value on confirm, or null on
/// cancel/dismiss. Mirrors `Downloads.tsx`'s `DeleteDialog` /
/// `DownloadDetail.tsx`'s `DeleteConfirm`.
Future<bool?> showDownloadDeleteDialog(
  BuildContext context, {
  required String name,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _DeleteDialog(name: name),
  );
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.name});
  final String name;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Material(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.35)),
                        ),
                        child: const Icon(Icons.delete_outline,
                            size: 20, color: AppColors.red),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text('Remove download?',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: wp.text,
                          )),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 14, height: 1.55, color: wp.dim),
                      children: [
                        TextSpan(
                          text: widget.name,
                          style: TextStyle(
                              color: wp.text, fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(
                            text: ' will stop downloading and be removed.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    onTap: () => setState(() => _deleteFiles = !_deleteFiles),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: wp.text.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                        border: Border.all(color: wp.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Also delete downloaded files',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: wp.text)),
                                const SizedBox(height: 2),
                                Text(
                                    'Erase the data on disk, not just the download',
                                    style: TextStyle(
                                        fontSize: 12, color: wp.faint)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _deleteFiles,
                            onChanged: (v) => setState(() => _deleteFiles = v),
                            activeThumbColor: Colors.white,
                            activeTrackColor: wp.text.withValues(alpha: 0.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.secondary,
                          expand: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppButton(
                          label: 'Remove',
                          icon: Icons.delete_outline,
                          variant: AppButtonVariant.danger,
                          expand: true,
                          onPressed: () =>
                              Navigator.of(context).pop(_deleteFiles),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
