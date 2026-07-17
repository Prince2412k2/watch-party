import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/downloads_provider.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/download_poster.dart';
import 'media_row.dart';

/// Native on-device downloads (PLAN §4 E8.2) — resumable cache fills, backed by
/// [downloadsProvider] (CacheFillController). Rows mirror the web
/// `DownloadProgress`: an active red dot, the title (red on error), a thin
/// progress bar (dim when paused), a mono `state · received/total · pct` line,
/// and pause/resume/cancel controls (Retry on failure).
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final downloads =
        ref
            .watch(downloadsProvider)
            .where(
              (d) =>
                  d.status != DownloadStatus.complete &&
                  d.status != DownloadStatus.canceled,
            )
            .toList()
          ..sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));

    return Scaffold(
      backgroundColor: wp.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Downloads', style: AppTheme.displaySmall.copyWith(color: wp.text)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Resumable, survives a restart — kill and reopen the app mid-download.',
                style: AppTheme.dim,
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: downloads.isEmpty
                    ? const EmptyState(
                        icon: Icons.download_outlined,
                        title: 'Nothing downloading',
                        message:
                            'Start a download from a title\'s detail page.',
                      )
                    : ListView.separated(
                        itemCount: downloads.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) => Reveal(
                          delay: AppMotion.stagger * math.min(i, 8),
                          child: _DownloadRow(record: downloads[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.record});
  final DownloadRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final notifier = ref.read(downloadsProvider.notifier);
    final paused = record.status == DownloadStatus.paused;
    final failed = record.status == DownloadStatus.failed;
    final running = record.status == DownloadStatus.running;
    final (label, _) = _statusLabel(record.status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: wp.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: wp.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (running) ...[
                const PulseDot(color: AppColors.live, size: 7),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  record.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: failed ? AppColors.red : wp.text,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTheme.mono.copyWith(
                  fontSize: 12,
                  color: failed
                      ? AppColors.red
                      : paused
                          ? wp.faint
                          : wp.dim,
                ),
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.error ?? 'Download failed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.red, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                AppButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  onPressed: () => notifier.resume(
                    record.taskId,
                    api: ref.read(apiClientProvider),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: LinearProgressIndicator(
                value: record.progress > 0
                    ? record.progress.clamp(0.0, 1.0)
                    : null,
                minHeight: 4,
                backgroundColor: wp.line2,
                color: paused ? wp.faint : wp.accent,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(record.progress * 100).round()}%'
                    '${record.totalBytes > 0 ? ' · ${_fmtBytes(record.bytesDownloaded)} / ${_fmtBytes(record.totalBytes)}' : ''}',
                    style: AppTheme.mono.copyWith(fontSize: 12, color: wp.dim),
                  ),
                ),
                MediaRowIconButton(
                  icon: paused ? Icons.play_arrow : Icons.pause,
                  tooltip: paused ? 'Resume' : 'Pause',
                  onPressed: () => paused
                      ? notifier.resume(
                          record.taskId,
                          api: ref.read(apiClientProvider),
                        )
                      : notifier.pause(record.taskId),
                ),
                MediaRowIconButton(
                  icon: Icons.close,
                  tooltip: 'Cancel',
                  color: AppColors.faint,
                  onPressed: () => notifier.cancel(record.taskId),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (String, bool) _statusLabel(DownloadStatus status) => switch (status) {
        DownloadStatus.enqueued => ('Queued', false),
        DownloadStatus.running => ('Downloading', false),
        DownloadStatus.paused => ('Paused', true),
        DownloadStatus.failed => ('Error', false),
        DownloadStatus.complete => ('Downloaded', false),
        DownloadStatus.canceled => ('Canceled', false),
      };

  static String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    if (bytes < 1024 * mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
  }
}
