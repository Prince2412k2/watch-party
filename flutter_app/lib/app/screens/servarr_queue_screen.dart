import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/download_poster.dart';
import 'download_detail_screen.dart';

/// Downloads — the server-side Radarr/Sonarr → qBittorrent acquisition surface.
/// Two sections: "Needs attention" (queue items stuck between grab and import,
/// as danger cards with an inline Cancel / Remove / Remove & block confirm) and
/// "Active" (a poster grid with circular progress rings + a DownloadDetail
/// overlay). Mirrors `app/client/src/pages/Downloads.tsx`.
///
/// NOT the native on-device offline downloads (`downloads_screen`) — this is the
/// acquisition queue the servarr stack is pulling down.
class ServarrQueueScreen extends ConsumerWidget {
  const ServarrQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(servarrHealthProvider);

    return health.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => ErrorState(
        title: 'Could not check service status',
        message: e.toString(),
      ),
      data: (h) {
        final qbitReady = servarrServiceReady(h, 'qbittorrent');
        final qbitConfigured =
            (h['services'] as Map?)?['qbittorrent'] is Map &&
                ((h['services'] as Map)['qbittorrent'] as Map)['configured'] ==
                    true;
        final arrReady = servarrServiceReady(h, 'radarr') ||
            servarrServiceReady(h, 'sonarr');
        return ListView(
          padding: const EdgeInsets.fromLTRB(44, 56, 44, 100),
          children: [
            if (arrReady) const _NeedsAttention(),
            _ActiveDownloads(
              qbitReady: qbitReady,
              qbitConfigured: qbitConfigured,
            ),
          ],
        );
      },
    );
  }
}

class _NeedsAttention extends ConsumerStatefulWidget {
  const _NeedsAttention();
  @override
  ConsumerState<_NeedsAttention> createState() => _NeedsAttentionState();
}

class _NeedsAttentionState extends ConsumerState<_NeedsAttention> {
  final _removed = <int>{};

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final snap = ref.watch(servarrFailingQueueProvider).valueOrNull;
    if (snap == null || !snap.loaded) return const SizedBox.shrink();

    final items = snap.items.where((q) => !_removed.contains(q.id)).toList();
    if (items.isEmpty && !snap.loadError) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Needs attention',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: items.isNotEmpty ? AppColors.red : wp.text,
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text('${items.length} stuck',
                    style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim)),
              ],
              if (snap.loadError) ...[
                const SizedBox(width: 10),
                const _Reconnecting(),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (items.isEmpty)
            Row(
              children: [
                Icon(Icons.check, size: 15, color: wp.faint),
                const SizedBox(width: 8),
                Text('Queue unavailable',
                    style: TextStyle(fontSize: 13, color: wp.faint)),
              ],
            )
          else
            StaggeredList(
              spacing: AppSpacing.md,
              children: [
                for (final q in items)
                  _FailingCard(
                    key: ValueKey('attn-${q.service}-${q.id}'),
                    item: q,
                    onRemove: (blocklist) {
                      setState(() => _removed.add(q.id));
                      ref
                          .read(servarrQueueActionsProvider)
                          .removeQueueItem(q, blocklist: blocklist);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FailingCard extends StatefulWidget {
  const _FailingCard({super.key, required this.item, required this.onRemove});
  final ServarrArrQueueItem item;
  final void Function(bool blocklist) onRemove;

  @override
  State<_FailingCard> createState() => _FailingCardState();
}

class _FailingCardState extends State<_FailingCard> {
  bool _confirm = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final q = widget.item;
    final metaLine =
        [q.indexer, fmtSize(q.size)].where((e) => e != null && e != '—').join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.error_outline,
                    size: 17, color: AppColors.red),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      q.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: wp.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final r in q.reasons)
                      Text(
                        r,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.red),
                      ),
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(metaLine,
                          style: AppTheme.mono.copyWith(
                              fontSize: 11.5, color: wp.faint)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!_confirm)
                MediaRowIconButtonLike(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove',
                  onTap: () => setState(() => _confirm = true),
                ),
            ],
          ),
          if (_confirm) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: wp.line)),
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Remove this download?',
                      style: TextStyle(fontSize: 12.5, color: wp.dim)),
                  const SizedBox(width: AppSpacing.sm),
                  _PillBtn(
                    label: 'Cancel',
                    onTap: () => setState(() => _confirm = false),
                  ),
                  _PillBtn(
                    label: 'Remove',
                    icon: Icons.delete_outline,
                    danger: true,
                    onTap: () => widget.onRemove(false),
                  ),
                  _PillBtn(
                    label: 'Remove & block',
                    icon: Icons.block,
                    danger: true,
                    onTap: () => widget.onRemove(true),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillBtn extends StatelessWidget {
  const _PillBtn({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final color = danger ? AppColors.red : wp.text;
    return Material(
      color: danger
          ? AppColors.red.withValues(alpha: 0.12)
          : wp.text.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        side: BorderSide(
          color: danger ? AppColors.red.withValues(alpha: 0.35) : wp.line2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveDownloads extends ConsumerStatefulWidget {
  const _ActiveDownloads({required this.qbitReady, required this.qbitConfigured});
  final bool qbitReady;
  final bool qbitConfigured;

  @override
  ConsumerState<_ActiveDownloads> createState() => _ActiveDownloadsState();
}

class _ActiveDownloadsState extends ConsumerState<_ActiveDownloads> {
  final _busy = <String>{};

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final actions = ref.read(servarrQueueActionsProvider);

    if (!widget.qbitReady) {
      return _Unavailable(
        text: widget.qbitConfigured
            ? 'Downloads unavailable'
            : 'Downloads not configured',
      );
    }

    final snap = ref.watch(servarrDownloadsPollProvider).valueOrNull;
    if (snap == null || !snap.loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final list = snap.list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.isNotEmpty || snap.loadError)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Active',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: wp.text,
                    )),
                if (list.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim),
                      children: [
                        TextSpan(
                          text:
                              '${snap.activeCount} active · ↓ ${fmtSpeed(snap.totalDlspeed)}',
                        ),
                        TextSpan(
                          text: ' · ↑ ${fmtSpeed(snap.totalUpspeed)}',
                          style: TextStyle(color: wp.faint),
                        ),
                      ],
                    ),
                  ),
                ],
                if (snap.loadError) ...[
                  const SizedBox(width: 10),
                  const _Reconnecting(),
                ],
              ],
            ),
          ),
        if (list.isEmpty)
          _Unavailable(text: 'No downloads', icon: Icons.download_outlined)
        else
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final t in list)
                _TorrentCard(
                  key: ValueKey('dl-${t.hash}'),
                  item: t,
                  busy: _busy.contains(t.hash),
                  onOpen: () => _openDetail(t),
                  onPauseResume: () {
                    if (t.isPaused) {
                      actions.resume(t.hash);
                    } else {
                      actions.pause(t.hash);
                    }
                  },
                  onDelete: () => _confirmDelete(t, actions),
                ),
            ],
          ),
      ],
    );
  }

  void _openDetail(ServarrDownload t) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadDetailScreen(hash: t.hash),
      ),
    );
  }

  Future<void> _confirmDelete(
      ServarrDownload t, ServarrQueueActions actions) async {
    final deleteFiles = await showDownloadDeleteDialog(context, name: t.name);
    if (deleteFiles == null || !mounted) return;
    setState(() => _busy.add(t.hash));
    await actions.deleteTorrent(t.hash, deleteFiles: deleteFiles);
    if (mounted) setState(() => _busy.remove(t.hash));
  }
}

/// One active-download card: a [DownloadPoster] with the ring + DL dot, then the
/// title and a mono `{state} · {subtitle | ↓ speed}` line and inline
/// pause/resume + delete controls. Tapping the poster opens the detail overlay.
class _TorrentCard extends StatelessWidget {
  const _TorrentCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onOpen,
    required this.onPauseResume,
    required this.onDelete,
  });
  final ServarrDownload item;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onPauseResume;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final info = item.stateInfo;
    final done = item.percent >= 100;
    final subtitle = (item.subtitle != null && item.subtitle!.isNotEmpty)
        ? item.subtitle!
        : '↓ ${fmtSpeed(item.dlspeed)}';
    final statusColor = info.label == 'Error'
        ? AppColors.red
        : (info.paused ? wp.faint : wp.dim);

    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onOpen,
              child: DownloadPoster(
                posterUrl: item.posterUrl,
                kind: item.kind,
                pct: item.percent.toDouble(),
                paused: info.paused,
                width: 160,
                ringSize: 78,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name.isEmpty ? '—' : item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: wp.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${info.label} · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono.copyWith(
                        fontSize: 11.5,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              MediaRowIconButtonLike(
                icon: info.paused ? Icons.play_arrow : Icons.pause,
                tooltip: info.paused ? 'Resume' : 'Pause',
                disabled: busy || done,
                onTap: onPauseResume,
              ),
              const SizedBox(width: 6),
              MediaRowIconButtonLike(
                icon: Icons.delete_outline,
                tooltip: 'Remove',
                danger: true,
                disabled: busy,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small bordered icon button matching the web `RowBtn` (used for card + card
/// controls). Named to avoid colliding with [MediaRowIconButton].
class MediaRowIconButtonLike extends StatefulWidget {
  const MediaRowIconButtonLike({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.disabled = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final bool disabled;

  @override
  State<MediaRowIconButtonLike> createState() => _MediaRowIconButtonLikeState();
}

class _MediaRowIconButtonLikeState extends State<MediaRowIconButtonLike> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final color = widget.danger
        ? (_hover ? AppColors.red : wp.dim)
        : (_hover ? wp.text : wp.dim);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.disabled ? null : widget.onTap,
          child: Opacity(
            opacity: widget.disabled ? 0.4 : 1,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _hover
                    ? (widget.danger
                        ? AppColors.red.withValues(alpha: 0.12)
                        : wp.text.withValues(alpha: 0.07))
                    : wp.text.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: wp.line),
              ),
              child: Icon(widget.icon, size: 16, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _Reconnecting extends StatelessWidget {
  const _Reconnecting();
  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
        const SizedBox(width: 6),
        Text('reconnecting…',
            style: AppTheme.mono.copyWith(fontSize: 12, color: wp.faint)),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.text, this.icon = Icons.download});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      constraints: const BoxConstraints(minHeight: 300),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: wp.faint),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(fontSize: 13, color: wp.faint)),
        ],
      ),
    );
  }
}
