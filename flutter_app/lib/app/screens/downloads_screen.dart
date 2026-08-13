import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/chrome.dart';
import '../../models/models.dart';
import '../../state/offline_provider.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/download_poster.dart';
import 'media_row.dart';
import 'servarr_queue_screen.dart';

/// Which set of downloads the screen is showing.
enum DownloadsScope {
  /// This device: what you have pulled down to watch offline.
  device,

  /// The server: what Radarr/Sonarr → qBittorrent is fetching onto the box
  /// everybody streams from. The administrator's, because acting on it is.
  server,
}

/// Everything you have downloaded or are downloading, in one list.
///
/// It used to show only what was in flight, and a download DISAPPEARED from
/// this screen the moment it finished — completing moved it to a separate
/// "Downloaded" tab that signed-in users could not even reach. So the tab named
/// Downloads was the one place your downloads were not, and finishing one
/// looked exactly like losing it.
///
/// Now the in-flight records and the finished ones render together, newest
/// activity first, with the finished ones deletable in place.
///
/// An administrator gets a second tab here: the server's own acquisition queue,
/// which was a page of its own at `/servarr/queue` that nothing in the nav
/// pointed at. Two kinds of "downloading" under one word was the confusion —
/// they are now two positions under one heading, which is what they are. A
/// member has only the one, so no tabs are drawn at all: a single tab is a
/// control that lies about being one.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  DownloadsScope _scope = DownloadsScope.device;

  @override
  void initState() {
    super.initState();
    // Opening the tab is when a stale download is worth noticing, and it is
    // cheap: one request per downloaded title, only on this screen, and only a
    // definitive 404 removes anything. Off the first frame so it cannot delay
    // the paint, and unawaited because nothing here waits on the answer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(offlineProvider.notifier)
            .reconcileWithLibrary(ref.read(apiClientProvider)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final canSeeServer = ref.watch(isAdminProvider);
    // Losing the admin flag mid-session (a demotion, a re-login as someone
    // else) must not leave the screen parked on a tab that is no longer there.
    final scope = canSeeServer ? _scope : DownloadsScope.device;
    final active =
        ref
            .watch(downloadsProvider)
            .where(
              (d) =>
                  d.status != DownloadStatus.complete &&
                  d.status != DownloadStatus.canceled,
            )
            .toList()
          ..sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
    // Finished titles live in the offline manifest, not in the download list —
    // completing hands the record over. Both are shown here.
    final done = ref.watch(offlineProvider);
    final rows = <Widget>[
      for (final d in active) _DownloadRow(record: d),
      for (final r in done) _CompletedRow(record: r),
    ];

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
                scope == DownloadsScope.device
                    ? 'Resumable, survives a restart, and retries itself when '
                          'the network drops.'
                    : 'What the server is fetching for everyone — the *arr '
                          'queue and the download client behind it.',
                style: AppTheme.dim,
              ),
              if (canSeeServer) ...[
                const SizedBox(height: AppSpacing.lg),
                AnalogSegmented<DownloadsScope>(
                  semanticLabel: 'Downloads',
                  value: scope,
                  segments: const [
                    AnalogSegment(
                      value: DownloadsScope.device,
                      label: 'This device',
                    ),
                    AnalogSegment(
                      value: DownloadsScope.server,
                      label: 'Server',
                    ),
                  ],
                  onChanged: (next) => setState(() => _scope = next),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: switch (scope) {
                  // The server queue is its own page's worth of content (stuck
                  // grabs, the live poster grid), rendered here rather than
                  // restated — `/servarr/queue` still routes to the same thing.
                  DownloadsScope.server => const ServarrQueueScreen(
                    padding: EdgeInsets.only(bottom: 100),
                  ),
                  DownloadsScope.device when rows.isEmpty => const EmptyState(
                    icon: Icons.download_outlined,
                    title: 'Nothing downloaded yet',
                    message: 'Start a download from a title\'s detail page.',
                  ),
                  DownloadsScope.device => ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) => Reveal(
                      delay: AppMotion.stagger * math.min(i, 8),
                      child: rows[i],
                    ),
                  ),
                },
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

/// A title that finished downloading and is sitting on this device.
///
/// Deliberately the same card as an in-flight row rather than a poster tile:
/// this list is one timeline of "what have I downloaded", and a finished item
/// changing shape would read as a different kind of thing rather than the same
/// thing further along.
class _CompletedRow extends ConsumerWidget {
  const _CompletedRow({required this.record});

  final OfflineRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
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
      child: Row(
        children: [
          const Icon(
            Icons.download_done_outlined,
            size: 18,
            color: AppColors.green,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              record.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: wp.text,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'On this device',
            style: AppTheme.mono.copyWith(fontSize: 12, color: wp.dim),
          ),
          const SizedBox(width: AppSpacing.sm),
          MediaRowIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete from this device',
            color: AppColors.faint,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  /// Deleting frees real disk and cannot be undone without downloading the
  /// whole film again, so it asks — unlike cancelling a download in progress,
  /// which throws away only what has not finished arriving.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirm(
      context,
      title: 'Delete download?',
      body: '${record.title} will be deleted from this device.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    await ref.read(offlineProvider.notifier).remove(record.itemId);
  }
}
