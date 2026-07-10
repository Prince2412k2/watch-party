import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import 'media_row.dart';

/// E9 T9.2 — Acquisition queue monitor: active torrents/usenet the servarr
/// stack (Radarr/Sonarr → qBittorrent) is pulling down, plus anything stuck
/// between grab and import ("needs attention"). Mirrors
/// `app/client/src/pages/Downloads.jsx`.
///
/// NOT the same thing as E8.2's native offline downloads (`downloads_screen`
/// / `offline_screen`, which track files the *phone* has saved for
/// no-network playback) — this screen only exists because the acquisition
/// side needed its own home; named `servarr_queue_screen.dart` specifically
/// to avoid colliding with E8.2's file.
class ServarrQueueScreen extends ConsumerWidget {
  const ServarrQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(servarrHealthProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Downloads',
            subtitle:
                'Everything currently downloading, plus anything stuck along the way.',
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: health.when(
              loading: () => const _QueueSkeleton(),
              error: (e, _) => ErrorState(
                title: 'Could not check service status',
                message: e.toString(),
              ),
              data: (h) {
                final qbitReady = servarrServiceReady(h, 'qbittorrent');
                final arrReady =
                    servarrServiceReady(h, 'radarr') ||
                    servarrServiceReady(h, 'sonarr');
                if (!qbitReady && !arrReady) {
                  return const EmptyState(
                    title: 'Downloads are unavailable',
                    message:
                        'No acquisition service is configured or reachable right now.',
                    icon: Icons.cloud_off_outlined,
                  );
                }
                return ListView(
                  children: [
                    if (arrReady) _NeedsAttention(),
                    const SizedBox(height: AppSpacing.xl),
                    if (qbitReady)
                      _ActiveDownloads()
                    else
                      const EmptyState(
                        title: 'qBittorrent unavailable',
                        icon: Icons.cloud_off_outlined,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failing = ref.watch(servarrFailingQueueProvider);
    final actions = ref.read(servarrQueueActionsProvider);

    return failing.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: MediaRowSkeleton(),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Needs attention'),
            StaggeredList(
              spacing: AppSpacing.sm,
              children: [
                for (final item in items)
                  MediaRow(
                    key: ValueKey('attn-${item.service}-${item.id}'),
                    leading: const MediaRowIcon(
                      icon: Icons.error_outline,
                      color: AppColors.red,
                    ),
                    title: item.title,
                    badge: const AppChip(
                      label: 'Stuck',
                      tone: AppChipTone.danger,
                    ),
                    subtitle:
                        item.errorMessage ?? item.statusMessages.join(' · '),
                    subtitleMaxLines: 2,
                    trailing: MediaRowIconButton(
                      icon: Icons.close,
                      tooltip: 'Remove',
                      color: AppColors.dim,
                      onPressed: () => actions.removeQueueItem(item),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ActiveDownloads extends ConsumerWidget {
  const _ActiveDownloads();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(servarrDownloadsPollProvider);
    final actions = ref.read(servarrQueueActionsProvider);

    return downloads.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SectionHeader(title: 'Active'),
          MediaRowSkeleton(withThumb: true),
          SizedBox(height: AppSpacing.sm),
          MediaRowSkeleton(withThumb: true),
          SizedBox(height: AppSpacing.sm),
          MediaRowSkeleton(withThumb: true),
        ],
      ),
      error: (e, _) =>
          ErrorState(title: 'Could not load downloads', message: e.toString()),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            title: 'Nothing downloading',
            message: 'Requests from Find & Download will show up here.',
            icon: Icons.download_outlined,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Active'),
            StaggeredList(
              spacing: AppSpacing.sm,
              children: [
                for (final d in items)
                  _DownloadRow(
                    key: ValueKey('dl-${d.hash}'),
                    item: d,
                    actions: actions,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({super.key, required this.item, required this.actions});
  final ServarrDownload item;
  final ServarrQueueActions actions;

  @override
  Widget build(BuildContext context) {
    return MediaRow(
      leading: MediaThumb(posterUrl: item.posterUrl),
      title: item.name.isEmpty ? '—' : item.name,
      subtitle: item.subtitle,
      showProgress: true,
      progress: item.progress.clamp(0.0, 1.0),
      meta:
          '${item.percent}% · ${_fmtSpeed(item.dlspeed)} · seeds ${item.numSeeds}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaRowIconButton(
            icon: item.isPaused ? Icons.play_arrow : Icons.pause,
            tooltip: item.isPaused ? 'Resume' : 'Pause',
            color: AppColors.dim,
            onPressed: () => item.isPaused
                ? actions.resume(item.hash)
                : actions.pause(item.hash),
          ),
          MediaRowIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove',
            color: AppColors.red,
            onPressed: () =>
                actions.deleteTorrent(item.hash, deleteFiles: true),
          ),
        ],
      ),
    );
  }
}

/// Skeleton shown while the one-time service health check resolves.
class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        MediaRowSkeleton(withThumb: true),
        SizedBox(height: AppSpacing.sm),
        MediaRowSkeleton(withThumb: true),
        SizedBox(height: AppSpacing.sm),
        MediaRowSkeleton(withThumb: true),
      ],
    );
  }
}

String _fmtSpeed(int bytesPerSec) {
  if (bytesPerSec <= 0) return '—';
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var value = bytesPerSec.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[i]}';
}
