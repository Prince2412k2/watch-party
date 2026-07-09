import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';

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
            subtitle: 'Everything currently downloading, plus anything stuck along the way.',
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: health.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(title: 'Could not check service status', message: e.toString()),
              data: (h) {
                final qbitReady = servarrServiceReady(h, 'qbittorrent');
                final arrReady = servarrServiceReady(h, 'radarr') || servarrServiceReady(h, 'sonarr');
                if (!qbitReady && !arrReady) {
                  return const EmptyState(
                    title: 'Downloads are unavailable',
                    message: 'No acquisition service is configured or reachable right now.',
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
                      const EmptyState(title: 'qBittorrent unavailable', icon: Icons.cloud_off_outlined),
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
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Needs attention'),
            for (final item in items)
              Card(
                color: AppColors.surface,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  side: const BorderSide(color: AppColors.line),
                ),
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: AppColors.red),
                  title: Text(item.title, style: AppTheme.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    item.errorMessage ?? item.statusMessages.join(' · '),
                    style: AppTheme.dim,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: AppColors.dim),
                    tooltip: 'Remove',
                    onPressed: () => actions.removeQueueItem(item),
                  ),
                ),
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
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorState(title: 'Could not load downloads', message: e.toString()),
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
            for (final d in items) _DownloadRow(item: d, actions: actions),
          ],
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.item, required this.actions});
  final ServarrDownload item;
  final ServarrQueueActions actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: SizedBox(
                width: 46, height: 69,
                child: item.posterUrl != null
                    ? Image.network(item.posterUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surface2))
                    : const ColoredBox(
                        color: AppColors.surface2,
                        child: Icon(Icons.movie_outlined, color: AppColors.faint, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name.isEmpty ? '—' : item.name,
                      style: AppTheme.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.subtitle != null)
                    Text(item.subtitle!, style: AppTheme.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    child: LinearProgressIndicator(
                      value: item.progress.clamp(0, 1),
                      minHeight: 5,
                      backgroundColor: AppColors.line2,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${item.percent}% · ${_fmtSpeed(item.dlspeed)} · seeds ${item.numSeeds}',
                    style: AppTheme.mono,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: Icon(item.isPaused ? Icons.play_arrow : Icons.pause, color: AppColors.dim),
              tooltip: item.isPaused ? 'Resume' : 'Pause',
              onPressed: () =>
                  item.isPaused ? actions.resume(item.hash) : actions.pause(item.hash),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.red),
              tooltip: 'Remove',
              onPressed: () => actions.deleteTorrent(item.hash, deleteFiles: true),
            ),
          ],
        ),
      ),
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
