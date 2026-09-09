import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import 'range_cache_store.dart';

/// A remote HTTP response together with the [HttpClient] that produced it —
/// the client must stay alive (and get closed) for as long as the response
/// body is being drained.
class _Upstream {
  _Upstream(this.response, this.client);
  final HttpClientResponse response;
  final HttpClient client;

  void close() => client.close(force: true);
}

/// One `[present-run | gap | present-run | …]` step of a request's byte
/// range, in the order they need to be written to the client response.
class _Segment {
  const _Segment.present(this.start, this.end) : isPresent = true;
  const _Segment.missing(this.start, this.end) : isPresent = false;
  final int start;
  final int end;
  final bool isPresent;
}

/// Local caching proxy the player opens instead of the signed native-stream
/// URL directly (on-device media cache, Phase 2).
///
/// ```
/// mpv --(GET /m/<itemId>, Range: …)--> MediaCacheProxy --> RangeCacheStore
///                                            |                  ^ hit
///                                            v miss             |
///                                     re-mint signed URL -> Jellyfin (via server)
/// ```
///
/// Only the network playback path is routed through this — a fully
/// downloaded offline file still plays straight from disk
/// (`openPreferringOffline` in `player/offline_playback.dart` is untouched).
/// Phase 3 will teach the downloader to fill this same [RangeCacheStore]
/// instead of writing a separate file, and add eviction; neither exists yet.
class MediaCacheProxy {
  MediaCacheProxy({
    required ApiClient apiClient,
    RangeCacheStore? store,
    this.requestTimeout = const Duration(seconds: 30),
  }) : // Keep the public parameter name distinct from the private field.
       // ignore: prefer_initializing_formals
       _apiClient = apiClient,
       _origin = apiClient.baseUrl,
       _store = store ?? RangeCacheStore(namespace: apiClient.baseUrl);

  final ApiClient _apiClient;
  RangeCacheStore _store;
  final Duration requestTimeout;
  int _generation = 0;
  final Map<HttpClient, String> _clients = {};
  final Map<String, int> _itemGenerations = {};
  final Map<CacheEntry, int> _entryGenerations = {};
  String _origin;
  String get origin => _origin;

  String _key(String itemId, String? source) => source == null
      ? itemId
      : 'source-${sha256.convert(utf8.encode(jsonEncode([itemId, source])))}';

  void abortItem(String itemId) {
    _itemGenerations[itemId] = (_itemGenerations[itemId] ?? 0) + 1;
    for (final client in _clients.keys.toList()) {
      if (_clients[client] == itemId) client.close(force: true);
    }
  }

  void stopTransfers() {
    _generation++;
    for (final client in _clients.keys.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }

  Future<void> changeOrigin(String origin) async {
    stopTransfers();
    final old = _store;
    _store = old.forNamespace(origin);
    _origin = origin;
    _entryGenerations.clear();
    await old.dispose();
  }

  HttpServer? _server;

  /// How far past a served request to keep fetching in the background so the
  /// next chunk of playback is already cached by the time mpv asks for it.
  static const _readAheadWindow = 96 * 1024 * 1024; // 96 MiB

  /// Default read-ahead chunk size; independent of proactive downloads.
  static const fetchChunkSize = 1 * 1024 * 1024;

  /// Amortizes URL minting and connection setup without parallel fetches.
  static const downloadChunkSize = 8 * 1024 * 1024;

  /// Titles with a read-ahead pass currently running — guards against
  /// stacking up unbounded background fetches for the same title (one
  /// sequential read-ahead pass per title at a time; a client seek just
  /// fetches its target range on demand instead of waiting on this).
  final Set<String> _readAheadInFlight = {};

  int? get port => _server?.port;

  /// Starts the local server. Idempotent — a second call while already
  /// running is a no-op.
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      _handleRequest,
      onError: (_) {}, // a single bad request must not take the server down
    );
  }

  Future<void> dispose() async {
    stopTransfers();
    await _server?.close(force: true);
    _server = null;
    await _store.dispose();
  }

  /// The URL the player should open for [itemId] in place of a direct signed
  /// stream URL. Throws [StateError] if [start] hasn't been awaited yet.
  String urlFor(String itemId, {String? mediaSourceId}) {
    final p = port;
    if (p == null) {
      throw StateError('MediaCacheProxy.start() must complete before urlFor()');
    }
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: p,
      pathSegments: ['m', itemId],
      queryParameters: mediaSourceId == null
          ? {'session': '$_generation'}
          : {'mediaSourceId': mediaSourceId, 'session': '$_generation'},
    ).toString();
  }

  /// Cached spans for [itemId] as 0..1 fractions of its total length, for the
  /// player's seek-bar "downloaded" overlay. Safe to call before playback has
  /// started for this title — starts empty and fills in as the proxy serves
  /// and read-aheads bytes.
  ValueListenable<List<CachedSpan>> cachedSpansFor(String itemId) =>
      _store.cachedSpansFor(itemId);

  /// Opens (or returns the already-open) [CacheEntry] for [itemId]. Exposed
  /// so callers that need to plan fetches against the raw entry (the
  /// download-fill controller, in particular) don't need their own
  /// [RangeCacheStore] — there's exactly one per proxy.
  Future<CacheEntry> openEntry(String itemId, {String? mediaSourceId}) async {
    final generation = _generation;
    final entry = await _store.open(_key(itemId, mediaSourceId));
    if (generation != _generation) throw StateError('Cache session changed');
    _entryGenerations[entry] = generation;
    return entry;
  }

  /// Bumps [itemId]'s [CacheEntry.lastAccess] to now, without touching cache
  /// contents — used by the fill controller to mark a just-completed
  /// download as freshest before running an eviction pass.
  Future<void> touch(String itemId) async {
    final entry = await _store.open(itemId);
    await entry.touch();
  }

  /// Whether [itemId]'s cache entry fully covers the title — i.e. it's
  /// "downloaded" and playable with no network (Phase 3b: download == a
  /// fully-filled cache entry, so this is the single source of truth
  /// `offlineProvider` rehydrates from).
  Future<bool> isComplete(String itemId) => _store.isComplete(itemId);

  /// Every itemId whose cache entry is fully present on disk.
  Future<List<String>> completedItemIds() => _store.completedItemIds();

  /// Deletes [itemId]'s cached bytes entirely — used when the user removes an
  /// offline title.
  Future<void> deleteEntry(String itemId) {
    abortItem(itemId);
    return _store.delete(itemId);
  }

  /// Runs one size-cap + 30-day-TTL eviction pass over the on-device cache
  /// (see [RangeCacheStore.evict]). Called once at boot (after [start]) so
  /// the cache doesn't grow unbounded across app runs; Phase 3b's
  /// download-fill can call this again after writing to keep the cap honest
  /// between app launches too. [protected] itemIds (e.g. whatever's about to
  /// play) are never evicted, on top of anything currently open/in-use.
  Future<void> evict({Set<String> protected = const {}}) =>
      _store.evict(protected: protected);

  /// Drops every cached title except [protected], regardless of size or age.
  /// The user asking for their disk back — see [RangeCacheStore.clear].
  Future<int> clear({Set<String> protected = const {}}) =>
      _store.clear(protected: protected);

  // ── Request handling ──────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (request.uri.queryParameters['session'] != '$_generation') {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
        return;
      }
      if (segments.length != 2 || segments[0] != 'm' || segments[1].isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      await _serve(
        request,
        segments[1],
        mediaSourceId: request.uri.queryParameters['mediaSourceId'],
      );
    } catch (_) {
      // Client disconnects surface here too (broken pipe writing the
      // response) — never let one request crash the server.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serve(
    HttpRequest request,
    String itemId, {
    String? mediaSourceId,
  }) async {
    final generation = _generation;
    final entry = await openEntry(itemId, mediaSourceId: mediaSourceId);
    await entry.touch();
    if (generation != _generation) throw StateError('Cache session changed');

    var total = entry.totalLength;
    if (total == null) {
      total = await _learnTotalLength(
        itemId,
        entry,
        mediaSourceId: mediaSourceId,
      );
      if (total == null) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
    }

    if (generation != _generation) throw StateError('Cache session changed');
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int start;
    int end; // exclusive
    final isRangeRequest = rangeHeader != null;
    if (rangeHeader != null) {
      final parsed = _parseRangeHeader(rangeHeader, total);
      if (parsed == null) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$total',
        );
        await request.response.close();
        return;
      }
      start = parsed.$1;
      end = parsed.$2;
    } else {
      start = 0;
      end = total;
    }

    final response = request.response;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType('video', 'mp4');
    response.headers.contentLength = end - start;
    if (isRangeRequest) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${end - 1}/$total',
      );
    } else {
      response.statusCode = HttpStatus.ok;
    }

    try {
      await _streamRange(
        entry,
        itemId,
        start,
        end,
        response,
        mediaSourceId: mediaSourceId,
      );
    } catch (_) {
      // Client aborted mid-response, or the upstream fetch failed after we'd
      // already committed headers — nothing more we can do for this request.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }

    // Fire-and-forget: keep filling the cache beyond what was just served.
    if (generation != _generation) return;
    unawaited(
      _readAhead(entry, itemId, end, total, mediaSourceId: mediaSourceId),
    );
  }

  /// Serves `[start, end)` to [response], reading present sub-ranges from the
  /// cache and fetching+forwarding+storing missing ones, in order.
  Future<void> _streamRange(
    CacheEntry entry,
    String itemId,
    int start,
    int end,
    HttpResponse response, {
    String? mediaSourceId,
  }) async {
    final generation = _generation;
    final gaps = entry.missingRanges(start, end);
    final segments = <_Segment>[];
    var cursor = start;
    for (final gap in gaps) {
      if (gap.start > cursor) segments.add(_Segment.present(cursor, gap.start));
      segments.add(_Segment.missing(gap.start, gap.end));
      cursor = gap.end;
    }
    if (cursor < end) segments.add(_Segment.present(cursor, end));

    for (final segment in segments) {
      if (generation != _generation) throw StateError('Cache session changed');
      if (segment.isPresent) {
        await for (final data in entry.readChunks(
          segment.start,
          segment.end,
          chunkSize: fetchChunkSize,
        )) {
          if (generation != _generation) {
            throw StateError('Cache session changed');
          }
          response.add(data);
          await response.flush().timeout(requestTimeout);
        }
      } else {
        await _fetchAndForward(
          entry,
          itemId,
          segment.start,
          segment.end,
          response,
          mediaSourceId: mediaSourceId,
        );
      }
    }
  }

  Future<void> _fetchAndForward(
    CacheEntry entry,
    String itemId,
    int start,
    int end,
    HttpResponse response, {
    String? mediaSourceId,
  }) async {
    final generation = _generation;
    for (var pos = start; pos < end;) {
      if (generation != _generation) throw StateError('Cache session changed');
      final next = (pos + fetchChunkSize).clamp(0, end);
      await fetchAndStore(
        itemId,
        entry,
        pos,
        next,
        mediaSourceId: mediaSourceId,
      );
      response.add(await entry.read(pos, next));
      await response.flush().timeout(requestTimeout);
      pos = next;
    }
  }

  /// After a request is served, keeps fetching forward (bounded by
  /// [_readAheadWindow]) so upcoming playback hits cache. One pass per title
  /// at a time; on any fetch error the pass just stops early — the next
  /// on-demand request re-fetches whatever's still missing.
  Future<void> _readAhead(
    CacheEntry entry,
    String itemId,
    int from,
    int total, {
    String? mediaSourceId,
  }) async {
    final generation = _generation;
    final key = _key(itemId, mediaSourceId);
    if (_readAheadInFlight.contains(key)) return;
    _readAheadInFlight.add(key);
    try {
      final windowEnd = (from + _readAheadWindow).clamp(0, total);
      if (windowEnd <= from) return;
      final gaps = entry.missingRanges(from, windowEnd);
      for (final gap in gaps) {
        if (generation != _generation) return;
        try {
          await fetchAndStore(
            itemId,
            entry,
            gap.start,
            gap.end,
            mediaSourceId: mediaSourceId,
          );
        } catch (_) {
          return; // give up this pass; on-demand fetches will fill gaps later
        }
      }
    } finally {
      _readAheadInFlight.remove(key);
    }
  }

  /// Ensures [entry]'s [CacheEntry.totalLength] is known, learning it from
  /// the remote if necessary. Reusable by anything that needs the title's
  /// size before it can plan a fetch (the fill controller, in particular).
  Future<int?> ensureTotalLength(
    String itemId,
    CacheEntry entry, {
    String? mediaSourceId,
  }) async {
    final known = entry.totalLength;
    if (known != null) return known;
    return _learnTotalLength(itemId, entry, mediaSourceId: mediaSourceId);
  }

  /// Fetches `[start, end)` from the remote and writes it into [entry],
  /// chunked at [chunkSize] per upstream call (so a single caller-sized
  /// gap doesn't hold one giant HTTP response open, and a failure partway
  /// through still leaves earlier chunks cached). Persists metadata once at
  /// the end. Extracted out of the read-ahead loop so both it and the
  /// download-fill controller (Phase 3b) share one "fetch a range from remote
  /// and store it" implementation, including the single re-mint-on-401/403
  /// baked into [_fetchRemoteRange].
  ///
  /// Foreground playback uses this same validator in 1 MiB chunks before
  /// forwarding bytes; proactive downloads retain their 8 MiB cadence.
  Future<void> fetchAndStore(
    String itemId,
    CacheEntry entry,
    int start,
    int end, {
    String? mediaSourceId,
    int chunkSize = fetchChunkSize,
  }) async {
    final generation = _generation;
    final itemGeneration = _itemGenerations[itemId] ?? 0;
    if (chunkSize <= 0 || chunkSize > downloadChunkSize) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
    var pos = start;
    while (pos < end) {
      if (generation != _generation ||
          itemGeneration != (_itemGenerations[itemId] ?? 0)) {
        throw StateError('Cache transfer cancelled');
      }
      final chunkEnd = (pos + chunkSize) > end ? end : pos + chunkSize;
      await _validatedWrite(
        itemId,
        entry,
        pos,
        chunkEnd,
        mediaSourceId: mediaSourceId,
      );
      pos = chunkEnd;
    }
    await entry.flushMetadata();
  }

  // ── Remote fetch (mint + re-mint on expiry) ───────────────────────────

  /// Probes the remote with a 1-byte ranged GET purely to learn the title's
  /// total length from `Content-Range`, and opportunistically caches that
  /// first byte since we already paid for the round trip.
  Future<int?> _learnTotalLength(
    String itemId,
    CacheEntry entry, {
    String? mediaSourceId,
  }) async {
    await _validatedWrite(itemId, entry, 0, 1, mediaSourceId: mediaSourceId);
    await entry.flushMetadata();
    return entry.totalLength;
  }

  Future<void> _validatedWrite(
    String itemId,
    CacheEntry entry,
    int start,
    int end, {
    String? mediaSourceId,
  }) async {
    final generation = _generation;
    final itemGeneration = _itemGenerations[itemId] ?? 0;
    void check() {
      if (generation != _generation ||
          _origin != _apiClient.baseUrl ||
          entry.itemId != _key(itemId, mediaSourceId) ||
          itemGeneration != (_itemGenerations[itemId] ?? 0) ||
          (_entryGenerations[entry] ?? generation) != generation ||
          entry.closed) {
        throw StateError('Cache transfer cancelled');
      }
    }

    check();
    final upstream = await _fetchRemoteRange(
      itemId,
      start,
      end,
      mediaSourceId: mediaSourceId,
    );
    try {
      final res = upstream.response;
      final range = RegExp(
        r'^bytes (\d+)-(\d+)/(\d+)$',
      ).firstMatch(res.headers.value(HttpHeaders.contentRangeHeader) ?? '');
      final total = range == null ? null : int.tryParse(range.group(3)!);
      if (res.statusCode != HttpStatus.partialContent ||
          range == null ||
          int.tryParse(range.group(1)!) != start ||
          int.tryParse(range.group(2)!) != end - 1 ||
          total == null ||
          total < end ||
          (entry.totalLength != null && entry.totalLength != total) ||
          (res.contentLength >= 0 && res.contentLength != end - start) ||
          res.headers.value(HttpHeaders.contentEncodingHeader) != null) {
        throw HttpException('Invalid upstream range response');
      }
      final bytes = BytesBuilder(copy: false);
      await (() async {
        await for (final chunk in res) {
          check();
          if (bytes.length + chunk.length > end - start) {
            throw HttpException('Upstream range body is too long');
          }
          bytes.add(chunk);
        }
      })().timeout(requestTimeout);
      check();
      if (bytes.length != end - start) {
        throw HttpException('Upstream range body is too short');
      }
      if (entry.totalLength != null && entry.totalLength != total) {
        throw HttpException('Media length changed during range request');
      }
      entry.setTotalLength(total);
      await entry.write(start, bytes.takeBytes());
    } finally {
      _clients.remove(upstream.client);
      upstream.close();
    }
  }

  /// Fetches `[start, end)` from the remote signed URL, re-minting once if
  /// the signed token has expired (401/403) — the token embeds its own TTL
  /// server-side, so a long-idle title's stale link fails this way rather
  /// than at request time.
  Future<_Upstream> _fetchRemoteRange(
    String itemId,
    int start,
    int end, {
    String? mediaSourceId,
  }) async {
    final generation = _generation;
    final itemGeneration = _itemGenerations[itemId] ?? 0;
    Future<_Upstream> attempt(String url) async {
      if (generation != _generation ||
          itemGeneration != (_itemGenerations[itemId] ?? 0)) {
        throw StateError('Cache transfer cancelled');
      }
      final client = HttpClient()..autoUncompress = false;
      _clients[client] = itemId;
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(requestTimeout);
        req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${end - 1}');
        final res = await req.close().timeout(requestTimeout);
        return _Upstream(res, client);
      } catch (_) {
        _clients.remove(client);
        client.close(force: true);
        rethrow;
      }
    }

    var signed = await _apiClient
        .nativeStreamUrl(
          itemId,
          purpose: 'stream',
          mediaSourceId: mediaSourceId,
        )
        .timeout(requestTimeout);
    var upstream = await attempt(signed.url);
    if (upstream.response.statusCode == HttpStatus.unauthorized ||
        upstream.response.statusCode == HttpStatus.forbidden) {
      _clients.remove(upstream.client);
      upstream.close();
      signed = await _apiClient
          .nativeStreamUrl(
            itemId,
            purpose: 'stream',
            mediaSourceId: mediaSourceId,
          )
          .timeout(requestTimeout);
      upstream = await attempt(signed.url);
    }
    return upstream;
  }

  // ── Range header parsing ──────────────────────────────────────────────

  /// Parses a `Range: bytes=...` header against a known [total] length.
  /// Returns `(start, end)` (end exclusive) or null if unsatisfiable.
  (int, int)? _parseRangeHeader(String header, int total) {
    if (!header.startsWith('bytes=')) return null;
    final spec = header.substring('bytes='.length);
    final parts = spec.split('-');
    if (parts.length != 2) return null;
    final startStr = parts[0];
    final endStr = parts[1];

    if (startStr.isEmpty) {
      // Suffix range, e.g. "bytes=-500" == last 500 bytes.
      final suffixLen = int.tryParse(endStr);
      if (suffixLen == null || suffixLen <= 0) return null;
      final start = total - suffixLen < 0 ? 0 : total - suffixLen;
      return (start, total);
    }

    final start = int.tryParse(startStr);
    if (start == null || start < 0 || start >= total) return null;
    final end = endStr.isEmpty ? total : (int.tryParse(endStr) ?? -1) + 1;
    if (end <= start) return null;
    return (start, end > total ? total : end);
  }
}
