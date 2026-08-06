import '../cache/warm_queue.dart';
import 'catalog_repository.dart';

/// Warms catalog JSON for the surfaces one hop from where the user is.
///
/// [CatalogRepository] already yields its persisted copy before it re-fetches,
/// so a surface the user has opened before paints from disk instantly. The gap
/// this closes is the *first* open: nothing has ever written that key, so the
/// screen comes up on a skeleton and waits out a round trip. Warming puts the
/// key on disk while the user is still looking at something else.
///
/// Deliberately narrow, because an audit of this app found most of what looks
/// warmable already is:
///
/// * **The other browse type is free.** Movies and Shows are one request —
///   `browseByTypeProvider` filters a single `items` payload by type on the
///   client — so they share one cache key. Opening either warms both, and
///   there is nothing left for a prefetch to do.
/// * **Home and Latest are guest-only.** `/movies` renders `HomeScreen` only
///   while signed out, so warming `home`/`latest` for a signed-in user is work
///   nobody ever collects.
/// * **A series' seasons bypass the cache.** `_libraryShowInfo` calls
///   `api.children` directly rather than going through the repository, so
///   warming `children:<id>` would fill a key nothing reads.
///
/// What is genuinely cold is the title the user is about to open: `/detail/:id`
/// reads `item:<id>`, and nothing fetches it until the moment it is opened.
/// That is [warmItem], driven by focus.
class CatalogPrefetcher {
  CatalogPrefetcher(this._repository, {int maxConcurrent = 1})
    : _queue = WarmQueue(maxConcurrent: maxConcurrent);

  final CatalogRepository _repository;
  final WarmQueue _queue;

  /// The browse catalog. One slot: re-warming it is the same request.
  static const String _browseSlot = 'browse';

  /// The focused title's detail. One slot, replaced on every focus move.
  static const String _focusSlot = 'focus';

  int get inFlight => _queue.inFlight;
  int get pending => _queue.pending;

  Future<void> settle() => _queue.settle();

  void dispose() => _queue.dispose();

  /// Warm the browse catalog for a launch that lands somewhere else.
  ///
  /// A null [namespace] means nobody is signed in, and [CatalogRepository]
  /// does not persist for a null namespace — the request would be spent with
  /// nothing kept, so there is nothing to warm.
  void warmBrowse(String? namespace) {
    if (namespace == null) return;
    _queue.replace(_browseSlot, [
      (
        key: '$namespace|items',
        run: () => _drain(_repository.items(namespace)),
      ),
    ]);
  }

  /// Warm the focused title's detail — what `/detail/:id` opens on, and what
  /// the series show stage awaits before it can ask for anything else.
  ///
  /// Focus moves far faster than the network, so this *replaces* rather than
  /// queues: running a rail end to end leaves one warm in flight and one
  /// queued, not one per title the cursor passed over.
  void warmItem(String? namespace, String itemId) {
    if (namespace == null || itemId.isEmpty) return;
    _queue.replace(_focusSlot, [
      (
        key: '$namespace|item:$itemId',
        run: () => _drain(_repository.item(namespace, itemId)),
      ),
    ]);
  }

  /// Run the stream to completion, which is what persists the fresh copy —
  /// unlike artwork, stopping at the first emission would only re-read the
  /// stale value the repository already had.
  Future<void> _drain(Stream<Object?> stream) => stream.drain<void>();
}
