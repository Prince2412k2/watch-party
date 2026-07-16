import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/media_cache_proxy.dart';
import '../download/offline_manifest_store.dart';
import '../models/models.dart';
import 'providers.dart';

/// The offline (fully-cached) library (Phase 3b-wiring). A title counts as
/// "offline" purely by whether its [MediaCacheProxy]/[RangeCacheStore] entry
/// is fully present on disk — [_rehydrate] scans the cache for that, and
/// [markComplete] adds a record the moment a fill finishes (so the UI flips
/// live without waiting for the next boot). [OfflineManifestStore] is kept
/// only as a metadata sidecar (title/poster/runtime) — the bytes themselves
/// live in the cache, not in anything this class writes.
class OfflineNotifier extends StateNotifier<List<OfflineRecord>> {
  OfflineNotifier(this._proxy, {OfflineManifestStore? manifestStore})
      : _manifestStore = manifestStore ?? OfflineManifestStore(),
        super(const []) {
    _rehydrate();
  }

  final MediaCacheProxy _proxy;
  final OfflineManifestStore _manifestStore;

  Future<void> _rehydrate() async {
    final persisted = await _manifestStore.load();
    final byId = {for (final r in persisted) r.itemId: r};
    final completedIds = await _proxy.completedItemIds();

    // This runs fire-and-forget from the constructor; bail if the notifier
    // was disposed while the async scan was in flight (never happens in the
    // app, where it lives for the whole session, but does in tests).
    if (!mounted) return;

    final records = [
      for (final id in completedIds) byId[id] ?? _bareRecord(id),
    ];
    state = records;

    // Metadata for a title whose cache entry no longer fully exists (evicted,
    // manually deleted from disk, …) is stale — drop it so a future rehydrate
    // doesn't keep re-surfacing it.
    if (records.length != persisted.length) {
      await _manifestStore.save(records);
    }
  }

  OfflineRecord _bareRecord(String itemId) => OfflineRecord(
        itemId: itemId,
        title: itemId,
        filePath: '',
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
      );

  /// Called once a [CacheFillController] fill finishes for [itemId] — adds
  /// (or refreshes) its [OfflineRecord] and persists the metadata sidecar.
  /// `filePath` is left empty: playback always resolves via
  /// [MediaCacheProxy.urlFor], never a bare file path (see
  /// `openPreferringOffline`/`resolveOfflinePlayback` below).
  Future<void> markComplete({
    required String itemId,
    required String title,
    String? posterTag,
    int runTimeTicks = 0,
  }) async {
    upsert(OfflineRecord(
      itemId: itemId,
      title: title,
      filePath: '',
      runTimeTicks: runTimeTicks,
      posterTag: posterTag,
      downloadedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _manifestStore.save(state);
  }

  void upsert(OfflineRecord record) {
    state = [
      ...state.where((r) => r.itemId != record.itemId),
      record,
    ];
  }

  Future<void> remove(String itemId) async {
    await _proxy.deleteEntry(itemId);
    state = state.where((r) => r.itemId != itemId).toList();
    await _manifestStore.save(state);
  }
}

final offlineProvider =
    StateNotifierProvider<OfflineNotifier, List<OfflineRecord>>(
        (ref) => OfflineNotifier(ref.watch(mediaCacheProxyProvider)));

/// Playback should prefer the on-device cache once a title is fully offline.
/// Mirrors the web app's `native/useOffline.js` `resolveOfflinePlayback(itemId,
/// streamUrl)`: once [itemId] is offline, the URL is always
/// [MediaCacheProxy.urlFor] (the proxy serves it straight from disk — no
/// network involved when the entry is complete), else [streamUrl] unchanged.
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
  final isOffline = offline.any((r) => r.itemId == itemId);
  if (isOffline) {
    return OfflinePlayback(
      url: ref.read(mediaCacheProxyProvider).urlFor(itemId),
      offline: true,
    );
  }
  return OfflinePlayback(url: streamUrl, offline: false);
}
