import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../download/downloader.dart';
import '../models/models.dart';
import 'providers.dart';

/// The offline (fully-downloaded) library (PLAN §3.8 / E8.3). Rehydrated from
/// [Downloader]'s persisted manifest at startup so the library survives an
/// app restart with no network involved.
class OfflineNotifier extends StateNotifier<List<OfflineRecord>> {
  OfflineNotifier(this._downloader) : super(const []) {
    _rehydrate();
  }

  final Downloader _downloader;

  Future<void> _rehydrate() async {
    await _downloader.init();
    state = _downloader.offlineRecords;
  }

  void upsert(OfflineRecord record) {
    state = [
      ...state.where((r) => r.itemId != record.itemId),
      record,
    ];
  }

  Future<void> remove(String itemId) async {
    await _downloader.removeOffline(itemId);
    state = state.where((r) => r.itemId != itemId).toList();
  }
}

final offlineProvider =
    StateNotifierProvider<OfflineNotifier, List<OfflineRecord>>(
        (ref) => OfflineNotifier(ref.watch(downloaderProvider)));

/// Playback should prefer a downloaded file over the network stream. Mirrors
/// the web app's `native/useOffline.js` `resolveOfflinePlayback(itemId,
/// streamUrl)`: returns the local file path when [itemId] is fully
/// downloaded, else falls back to [streamUrl] unchanged.
class OfflinePlayback {
  const OfflinePlayback({required this.url, required this.offline});
  final String url;
  final bool offline;
}

OfflinePlayback resolveOfflinePlayback(
  Ref ref,
  String itemId,
  String streamUrl,
) {
  final offline = ref.read(offlineProvider);
  for (final record in offline) {
    if (record.itemId == itemId) {
      return OfflinePlayback(url: record.filePath, offline: true);
    }
  }
  return OfflinePlayback(url: streamUrl, offline: false);
}
