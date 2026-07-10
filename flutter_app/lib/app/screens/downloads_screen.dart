import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/downloads_provider.dart';
import '../../ui/ui.dart';

/// Active downloads (PLAN §4 E8.2) — replaces the E0 placeholder at
/// `/downloads`. Router wiring (already frozen, `lib/app/router.dart`):
///
/// ```dart
/// GoRoute(path: Routes.downloads, builder: (_, _) => const DownloadsScreen()),
/// ```
/// with `import '../screens/downloads_screen.dart';` swapped in for the
/// placeholder's `DownloadsScreen` import — this class keeps the same name so
/// that's the only change needed.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider)
        .where((d) => d.status != DownloadStatus.complete && d.status != DownloadStatus.canceled)
        .toList()
      ..sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Downloads', style: AppTheme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              const Text('Resumable, survives a restart — kill and reopen the app mid-download.',
                  style: AppTheme.dim),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: downloads.isEmpty
                    ? const EmptyState(
                        icon: Icons.download_outlined,
                        title: 'Nothing downloading',
                        message: 'Start a download from a title\'s detail page.',
                      )
                    : ListView.separated(
                        itemCount: downloads.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) => _DownloadRow(record: downloads[i]),
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
    final notifier = ref.read(downloadsProvider.notifier);
    final paused = record.status == DownloadStatus.paused;
    final failed = record.status == DownloadStatus.failed;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StatusChip(status: record.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (failed)
                  Text(record.error ?? 'Download failed',
                      style: const TextStyle(color: AppColors.red, fontSize: 12.5))
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: LinearProgressIndicator(
                      value: record.progress > 0 ? record.progress.clamp(0, 1) : null,
                      minHeight: 5,
                      backgroundColor: AppColors.line2,
                      color: paused ? AppColors.faint : AppColors.accent,
                    ),
                  ),
                if (!failed) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${(record.progress * 100).round()}%'
                    '${record.totalBytes > 0 ? ' · ${_fmtBytes(record.bytesDownloaded)} / ${_fmtBytes(record.totalBytes)}' : ''}',
                    style: AppTheme.caption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          if (failed)
            AppButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: () => notifier.resume(record.taskId),
            )
          else ...[
            IconButton(
              tooltip: paused ? 'Resume' : 'Pause',
              icon: Icon(paused ? Icons.play_arrow : Icons.pause, color: AppColors.text),
              onPressed: () => paused ? notifier.resume(record.taskId) : notifier.pause(record.taskId),
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, color: AppColors.faint),
              onPressed: () => notifier.cancel(record.taskId),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    if (bytes < 1024 * mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      DownloadStatus.enqueued => ('Queued', AppChipTone.neutral),
      DownloadStatus.running => ('Downloading', AppChipTone.neutral),
      DownloadStatus.paused => ('Paused', AppChipTone.neutral),
      DownloadStatus.failed => ('Failed', AppChipTone.danger),
      DownloadStatus.complete => ('Downloaded', AppChipTone.success),
      DownloadStatus.canceled => ('Canceled', AppChipTone.neutral),
    };
    return AppChip(label: label, tone: tone);
  }
}
