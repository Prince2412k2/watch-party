import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_button.dart';
import '../../analog/chrome/analog_progress.dart';
import '../../models/models.dart';
import '../../state/downloads_provider.dart';
import '../../state/offline_provider.dart';
import '../../state/providers.dart';
import '../analog_tokens.dart';
import 'chip.dart';

/// Download affordance for a title (PLAN §4 E8.2) — this is what E3's detail
/// screen mounts next to Play. Driven entirely by [downloadsProvider] (the
/// in-flight task, if any) and [offlineProvider] (the completed manifest):
///
///   nothing yet          → "Download" button.
///   enqueued/running      → progress bar + pause/cancel.
///   paused                → progress bar (dimmed) + resume/cancel.
///   failed                → error text + "Retry".
///   in the offline manifest → "Downloaded" chip + remove.
///
/// Starting a download fills the same on-device media cache playback streams
/// through (`CacheFillController.start`, Phase 3b-wiring) — a "download" is
/// just a fully-cached title, watchable while downloading and playable
/// offline once complete. Callers only need the item's id/title/metadata.
class DownloadButton extends ConsumerWidget {
  const DownloadButton({
    super.key,
    required this.itemId,
    required this.title,
    this.posterTag,
    this.runTimeTicks,
    this.container,
  });

  final String itemId;
  final String title;
  final String? posterTag;
  final int? runTimeTicks;
  final String? container;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = _findOffline(ref.watch(offlineProvider), itemId);
    if (offline != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppChip(
            label: 'Downloaded',
            tone: AppChipTone.success,
            icon: Icons.check,
          ),
          const SizedBox(width: AnalogSpace.smPx),
          AnalogIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove download',
            onPressed: () => ref.read(offlineProvider.notifier).remove(itemId),
          ),
        ],
      );
    }

    final download = _findDownload(ref.watch(downloadsProvider), itemId);
    if (download == null ||
        download.status == DownloadStatus.canceled ||
        download.status == DownloadStatus.complete) {
      // `complete` briefly races the offline-manifest write (E8.3 wiring) —
      // treat it the same as "not started" rather than flash a dead-end state.
      // Icon-only. A downward arrow into a tray is one of maybe five glyphs
      // that need no gloss anywhere on earth, and the word next to it was
      // costing 90px on a surface whose whole argument is that the artwork is
      // the interface. The tooltip is not a consolation prize — it is the
      // control's accessible name, and [AnalogIconButton] will not compile
      // without one.
      return AnalogIconButton(
        icon: Icons.download_outlined,
        tooltip: 'Download',
        tone: AnalogIconButtonTone.solid,
        onPressed: () => _start(ref),
      );
    }

    if (download.status == DownloadStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              download.error ?? 'Download failed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AnalogType.sansFamily,
                color: AnalogColor.statusDanger,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: AnalogSpace.smPx),
          // The failure message beside it is already carrying the words. A
          // "Retry" label here would be the second sentence about one event.
          AnalogIconButton(
            icon: Icons.refresh,
            tooltip: 'Retry the download',
            onPressed: () => _start(ref),
          ),
        ],
      );
    }

    return _ProgressRow(
      record: download,
      onPause: () =>
          ref.read(downloadsProvider.notifier).pause(download.taskId),
      onResume: () => ref
          .read(downloadsProvider.notifier)
          .resume(download.taskId, api: ref.read(apiClientProvider)),
      onCancel: () =>
          ref.read(downloadsProvider.notifier).cancel(download.taskId),
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

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.record,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final DownloadRecord record;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final paused = record.status == DownloadStatus.paused;
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: AnalogProgress(
                  value: record.progress > 0
                      ? record.progress.clamp(0.0, 1.0)
                      : null,
                  semanticLabel: 'Download progress',
                  // Paused is carried by the icon swapping to Play as well as
                  // by the line dimming, so it survives without the colour.
                  ink: paused ? AnalogColor.inkFaint : AnalogColor.ink,
                ),
              ),
              const SizedBox(width: AnalogSpace.smPx),
              Text(
                '${(record.progress * 100).round()}%',
                style: const TextStyle(
                  fontFamily: AnalogType.monoFamily,
                  fontSize: 11.5,
                  color: AnalogColor.inkDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: AnalogSpace.smPx),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnalogIconButton(
                icon: paused ? Icons.play_arrow : Icons.pause,
                tooltip: paused ? 'Resume' : 'Pause',
                onPressed: paused ? onResume : onPause,
              ),
              AnalogIconButton(
                icon: Icons.close,
                tooltip: 'Cancel',
                onPressed: onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
