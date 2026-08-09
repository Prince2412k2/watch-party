import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/media_cache_proxy.dart';
import '../data/api_client.dart';
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

  /// Serializes every read-modify-write of [state] + the manifest sidecar.
  /// [_rehydrate] runs fire-and-forget from the constructor and takes two
  /// awaits to assemble its list; without this queue a [markComplete] or
  /// [remove] landing in that window was silently overwritten by the scan's
  /// `state = records`, and both then persisted a list built from a snapshot
  /// that was already stale.
  Future<void> _queue = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    // Only the chain swallows failures (the caller still gets [result]), so one
    // failed persist can't wedge every later mutation behind a rejected future.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _rehydrate() => _serialize(() async {
        final persisted = await _manifestStore.load();
        final byId = {for (final r in persisted) r.itemId: r};
        final completedIds = await _proxy.completedItemIds();

        // This runs fire-and-forget from the constructor; bail if the notifier
        // was disposed while the async scan was in flight (never happens in the
        // app, where it lives for the whole session, but does in tests).
        if (!mounted) return;

        // Merge rather than replace: [upsert] is synchronous, so a record added
        // while the scan was in flight is newer than the scan's snapshot and
        // wins (a fill that completed mid-scan is genuinely offline, and its
        // metadata is richer than a bare record).
        final merged = <String, OfflineRecord>{
          for (final id in completedIds) id: byId[id] ?? _bareRecord(id),
        };
        for (final live in state) {
          merged[live.itemId] = live;
        }
        state = merged.values.toList(growable: false);

        // Metadata for a title whose cache entry no longer fully exists
        // (evicted, manually deleted from disk, …) is stale — drop it so a
        // future rehydrate doesn't keep re-surfacing it.
        final drifted = merged.length != persisted.length ||
            merged.keys.any((id) => !byId.containsKey(id));
        if (drifted) await _manifestStore.save(state);
      });

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
  }) =>
      _serialize(() async {
        if (!mounted) return;
        upsert(OfflineRecord(
          itemId: itemId,
          title: title,
          filePath: '',
          runTimeTicks: runTimeTicks,
          posterTag: posterTag,
          downloadedAt: DateTime.now().millisecondsSinceEpoch,
        ));
        await _manifestStore.save(state);
      });

  void upsert(OfflineRecord record) {
    state = [
      ...state.where((r) => r.itemId != record.itemId),
      record,
    ];
  }

  /// Drop downloads whose title no longer exists on the server.
  ///
  /// A film deleted from the library leaves its bytes on every device that had
  /// downloaded it — invisible, unplayable, and occupying gigabytes nobody can
  /// account for. This reclaims that.
  ///
  /// The dangerous version of this feature reconciles against a LISTING: fetch
  /// the library, remove anything not in it. That deletes every download you
  /// own the first time the request comes back empty, truncated, paged, or
  /// scoped to a different view — a transient server fault becomes permanent
  /// local data loss, and the user never asked for anything.
  ///
  /// So this only ever acts on a POSITIVE confirmation, per item: a 404 or 410
  /// for that specific id. Any other outcome — a network failure, a 500, a 401,
  /// a timeout — leaves the download exactly where it is. Being wrong in this
  /// direction costs disk space; being wrong in the other costs someone the
  /// film they downloaded for a flight.
  Future<void> reconcileWithLibrary(ApiClient api) async {
    final ids = state.map((r) => r.itemId).toList();
    for (final itemId in ids) {
      bool gone = false;
      try {
        await api.item(itemId);
      } on ApiException catch (e) {
        gone = e.statusCode == 404 || e.statusCode == 410;
      } catch (_) {
        // Not an answer. Say nothing, change nothing.
        continue;
      }
      if (gone) await remove(itemId);
    }
  }

  Future<void> remove(String itemId) => _serialize(() async {
        await _proxy.deleteEntry(itemId);
        if (!mounted) return;
        state = state.where((r) => r.itemId != itemId).toList();
        await _manifestStore.save(state);
      });
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
