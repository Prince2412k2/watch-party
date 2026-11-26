import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
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
  const DownloadDetailScreen({super.key, required this.hash, this.onClose});
  final String hash;

  /// How to leave this screen. Null pops the enclosing route, which is right
  /// when the queue pushed this on the root navigator; the `/downloads/:id`
  /// route passes its own, because a deep link straight to this screen has no
  /// route under it to pop back to.
  final VoidCallback? onClose;

  @override
  ConsumerState<DownloadDetailScreen> createState() =>
      _DownloadDetailScreenState();
}

class _DownloadDetailScreenState extends ConsumerState<DownloadDetailScreen> {
  bool _busy = false;
  ServarrDownload? _lastTorrent;
  bool _removed = false;

  void _close() {
    if (!mounted) return;
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final poll = ref.watch(servarrDownloadsPollProvider);
    final snap = poll.valueOrNull;
    final torrent = snap?.list.cast<ServarrDownload?>().firstWhere(
      (t) => t?.hash == widget.hash,
      orElse: () => null,
    );

    if (torrent != null) _lastTorrent = torrent;
    if (torrent == null || _removed) {
      final unavailable =
          !_removed && (poll.hasError || (snap?.loadError ?? false));
      final previous = _lastTorrent;
      if (_removed || unavailable || snap?.loaded == true) {
        return Scaffold(
          backgroundColor: wp.bg,
          body: EmptyState(
            title: _removed
                ? 'Removed from the server queue'
                : unavailable
                ? 'Unable to refresh the server queue'
                : previous != null && previous.percent >= 100
                ? 'Download left the queue after reaching 100%'
                : 'Download is no longer in the server queue',
            message: _removed
                ? previous?.name
                : unavailable
                ? 'The server did not return the current download status.'
                : 'The server no longer lists this download.',
            icon: Icons.download_done_outlined,
            actionLabel: unavailable ? 'Retry' : 'Back to downloads',
            onAction: unavailable
                ? () => ref.invalidate(servarrDownloadsPollProvider)
                : _close,
          ),
        );
      }
      return Scaffold(
        backgroundColor: wp.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final detail = ref
        .watch(servarrDownloadDetailProvider(widget.hash))
        .valueOrNull;
    final pct = torrent.percent;
    final paused = torrent.isPaused;
    final done = pct >= 100;

    final kind = detail?.kind ?? torrent.kind;
    final title = (detail?.title?.isNotEmpty == true
        ? detail!.title!
        : torrent.name);
    final subtitle = detail?.subtitle ?? torrent.subtitle;
    final posterUrl = detail?.posterUrl ?? torrent.posterUrl;
    final overview = detail?.overview;
    final genres = detail?.genres ?? const <String>[];
    final rating = detail?.rating;
    final runtime = fmtRuntimeFromMinutes(detail?.runtime);
    final infoLine = <String>[
      if (detail?.year != null) detail!.year!,
      ?runtime,
      if (detail?.certification != null && detail!.certification!.isNotEmpty)
        detail.certification!,
      if (detail?.network != null && detail!.network!.isNotEmpty)
        detail.network!,
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final poster = Container(
                            width: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusLg,
                              ),
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
                          );
                          final info = Column(
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
                                style: AppTheme.headlineLarge.copyWith(
                                  color: wp.text,
                                ),
                              ),
                              if (subtitle != null && subtitle.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  subtitle,
                                  style: AppTheme.mono.copyWith(
                                    fontSize: 13.5,
                                    color: wp.dim,
                                  ),
                                ),
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
                                      Text(
                                        v,
                                        style: AppTheme.mono.copyWith(
                                          fontSize: 13,
                                          color: wp.dim,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 22),
                              _StatsRow(
                                torrent: torrent,
                                done: done,
                                paused: paused,
                              ),
                              const SizedBox(height: 22),
                              Wrap(
                                spacing: AppSpacing.md,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  AppButton(
                                    label: paused ? 'Resume' : 'Pause',
                                    icon: paused
                                        ? Icons.play_arrow
                                        : Icons.pause,
                                    variant: AppButtonVariant.primary,
                                    onPressed: (_busy || done)
                                        ? null
                                        : _pauseResume,
                                  ),
                                  AppButton(
                                    label: 'Remove from server queue…',
                                    icon: Icons.delete_outline,
                                    variant: AppButtonVariant.secondary,
                                    onPressed: _busy
                                        ? null
                                        : () => _delete(title),
                                  ),
                                ],
                              ),
                            ],
                          );
                          if (constraints.maxWidth < 580) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                poster,
                                const SizedBox(height: 24),
                                info,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              poster,
                              const SizedBox(width: 28),
                              Expanded(child: info),
                            ],
                          );
                        },
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
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.65,
                          color: wp.dim,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 60),
              ],
            ),
          ),
          StageBackButton(onTap: _close),
        ],
      ),
    );
  }

  Future<void> _pauseResume() async {
    // Same nullable lookup as [build]. The previous `orElse` invented an
    // unpaused torrent when the hash had left the queue, so the button acted
    // on a download that no longer existed and reported nothing.
    final torrent = ref
        .read(servarrDownloadsPollProvider)
        .valueOrNull
        ?.list
        .cast<ServarrDownload?>()
        .firstWhere((t) => t?.hash == widget.hash, orElse: () => null);
    if (torrent == null) return;

    final resuming = torrent.isPaused;
    setState(() => _busy = true);
    try {
      final actions = ref.read(servarrQueueActionsProvider);
      if (resuming) {
        await actions.resume(widget.hash);
      } else {
        await actions.pause(widget.hash);
      }
    } catch (error) {
      _report(resuming ? 'Could not resume' : 'Could not pause', error);
    } finally {
      // In a `finally` because the alternative is what shipped: a request that
      // threw left every button on this screen disabled until the user backed
      // out and came in again, with nothing on screen to say why.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String name) async {
    final deleteFiles = await showDownloadDeleteDialog(context, name: name);
    if (deleteFiles == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servarrQueueActionsProvider)
          .deleteTorrent(widget.hash, deleteFiles: deleteFiles);
      if (mounted) setState(() => _removed = true);
    } catch (error) {
      _report('Could not remove from the server queue', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(String what, Object error) {
    if (!mounted) return;
    final reason = error is ApiException ? error.message : '$error';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what: $reason')));
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.torrent,
    required this.done,
    required this.paused,
  });
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
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 12,
      children: [
        DownloadRing(
          pct: torrent.percent.toDouble(),
          size: 104,
          stroke: 8,
          color: paused ? wp.dim : wp.text,
        ),
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
                decoration: BoxDecoration(
                  color: wp.faint,
                  shape: BoxShape.circle,
                ),
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
              Text(
                rating!.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: wp.text,
                ),
              ),
            ],
          ),
        for (final g in genres.take(3))
          Text(
            g,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: wp.dim,
            ),
          ),
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
                            color: AppColors.red.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          'Remove from server queue?',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: wp.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: wp.dim,
                      ),
                      children: [
                        TextSpan(
                          text: widget.name,
                          style: TextStyle(
                            color: wp.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(
                          text: ' will stop downloading and be removed.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    onTap: () => setState(() => _deleteFiles = !_deleteFiles),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
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
                                Text(
                                  'Also delete downloaded files',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: wp.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Erase the data on disk, not just the download',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: wp.faint,
                                  ),
                                ),
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
