import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_button.dart';
import '../../models/models.dart';
import '../../state/downloads_provider.dart';
import '../../state/offline_provider.dart';
import '../../state/providers.dart';
import 'download_actions.dart';

enum _DownloadAction { remove, pause, resume, retry, cancel }

/// A stable title action for starting and managing the device copy.
class DownloadButton extends ConsumerWidget {
  const DownloadButton({
    super.key,
    required this.itemId,
    required this.title,
    this.posterTag,
    this.runTimeTicks,
    this.container,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String itemId;
  final String title;
  final String? posterTag;
  final int? runTimeTicks;
  final String? container;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox.square(dimension: 44, child: _buildAction(context, ref));
  }

  Widget _buildAction(BuildContext context, WidgetRef ref) {
    final offline = _findOffline(ref.watch(offlineProvider), itemId);
    if (offline != null) {
      return PopupMenuButton<_DownloadAction>(
        tooltip: 'Downloaded · Manage device copy',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.download_done, size: 18),
        onSelected: (_) =>
            removeLocalDownload(context, ref, itemId: itemId, title: title),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _DownloadAction.remove,
            child: Text('Remove download from this device…'),
          ),
        ],
      );
    }

    final download = _findDownload(ref.watch(downloadsProvider), itemId);
    if (download == null ||
        download.status == DownloadStatus.canceled ||
        download.status == DownloadStatus.complete) {
      return AnalogIconButton(
        icon: Icons.download_outlined,
        tooltip: 'Download',
        tone: AnalogIconButtonTone.solid,
        size: 44,
        onPressed: () => _start(ref),
      );
    }

    final failed = download.status == DownloadStatus.failed;
    final paused = download.status == DownloadStatus.paused;
    final progress = download.progress.clamp(0.0, 1.0).toDouble();
    final percent = '${(progress * 100).round()}%';
    final status = switch (download.status) {
      DownloadStatus.enqueued => 'Download queued',
      DownloadStatus.failed => 'Download failed',
      DownloadStatus.paused => 'Download paused · $percent',
      _ => 'Downloading · $percent',
    };

    return PopupMenuButton<_DownloadAction>(
      tooltip: status,
      padding: EdgeInsets.zero,
      icon: failed
          ? const Icon(Icons.error_outline, size: 18)
          : Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    backgroundColor: Theme.of(context).dividerColor,
                  ),
                ),
                Icon(paused ? Icons.pause : Icons.download, size: 14),
              ],
            ),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(download.error ?? status)),
        if (failed)
          const PopupMenuItem(
            value: _DownloadAction.retry,
            child: Text('Retry download'),
          )
        else
          PopupMenuItem(
            value: paused ? _DownloadAction.resume : _DownloadAction.pause,
            child: Text(paused ? 'Resume download' : 'Pause download'),
          ),
        const PopupMenuItem(
          value: _DownloadAction.cancel,
          child: Text('Cancel download…'),
        ),
      ],
      onSelected: (action) async {
        final notifier = ref.read(downloadsProvider.notifier);
        switch (action) {
          case _DownloadAction.pause:
            await notifier.pause(download.taskId);
          case _DownloadAction.resume:
            await notifier.resume(
              download.taskId,
              api: ref.read(apiClientProvider),
            );
          case _DownloadAction.retry:
            await _start(ref);
          case _DownloadAction.cancel:
            await cancelLocalDownload(
              context,
              ref,
              taskId: download.taskId,
              title: title,
            );
          case _DownloadAction.remove:
            break;
        }
      },
    );
  }

  Future<void> _start(WidgetRef ref) => ref
      .read(downloadsProvider.notifier)
      .start(
        api: ref.read(apiClientProvider),
        itemId: itemId,
        title: title,
        posterTag: posterTag,
        runTimeTicks: runTimeTicks,
        container: container,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );

  static OfflineRecord? _findOffline(
    List<OfflineRecord> records,
    String itemId,
  ) {
    for (final r in records) {
      if (r.itemId == itemId) return r;
    }
    return null;
  }

  static DownloadRecord? _findDownload(
    List<DownloadRecord> records,
    String itemId,
  ) {
    for (final r in records) {
      if (r.itemId == itemId) return r;
    }
    return null;
  }
}
