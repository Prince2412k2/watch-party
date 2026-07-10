import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/downloads_provider.dart';
import '../../ui/ui.dart';
import 'media_row.dart';

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
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Downloads', style: AppTheme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              const Text(
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
                          // Index-delayed cascade in; capped so a long queue
                          // doesn't animate for seconds.
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
    final notifier = ref.read(downloadsProvider.notifier);
    final paused = record.status == DownloadStatus.paused;
    final failed = record.status == DownloadStatus.failed;

    if (failed) {
      return MediaRow(
        title: record.title,
        badge: _StatusChip(status: record.status),
        subtitle: record.error ?? 'Download failed',
        subtitleIsError: true,
        trailing: AppButton(
          label: 'Retry',
          icon: Icons.refresh,
          onPressed: () => notifier.resume(record.taskId),
        ),
      );
    }

    return MediaRow(
      title: record.title,
      badge: _StatusChip(status: record.status),
      showProgress: true,
      progress: record.progress > 0 ? record.progress.clamp(0.0, 1.0) : null,
      progressColor: paused ? AppColors.faint : AppColors.accent,
      meta:
          '${(record.progress * 100).round()}%'
          '${record.totalBytes > 0 ? ' · ${_fmtBytes(record.bytesDownloaded)} / ${_fmtBytes(record.totalBytes)}' : ''}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaRowIconButton(
            icon: paused ? Icons.play_arrow : Icons.pause,
            tooltip: paused ? 'Resume' : 'Pause',
            onPressed: () => paused
                ? notifier.resume(record.taskId)
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
