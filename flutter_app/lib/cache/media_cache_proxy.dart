import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  MediaCacheProxy({required ApiClient apiClient, RangeCacheStore? store})
      : _apiClient = apiClient,
        _store = store ?? RangeCacheStore();

  final ApiClient _apiClient;
  final RangeCacheStore _store;

  HttpServer? _server;

  /// How far past a served request to keep fetching in the background so the
  /// next chunk of playback is already cached by the time mpv asks for it.
  static const _readAheadWindow = 96 * 1024 * 1024; // 96 MiB
  static const _fetchChunkSize = 1 * 1024 * 1024; // 1 MiB per upstream call

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
    await _server?.close(force: true);
    _server = null;
  }

  /// The URL the player should open for [itemId] in place of a direct signed
  /// stream URL. Throws [StateError] if [start] hasn't been awaited yet.
  String urlFor(String itemId) {
    final p = port;
    if (p == null) {
      throw StateError('MediaCacheProxy.start() must complete before urlFor()');
    }
    return 'http://127.0.0.1:$p/m/$itemId';
  }

  /// Cached spans for [itemId] as 0..1 fractions of its total length, for the
  /// player's seek-bar "downloaded" overlay. Safe to call before playback has
  /// started for this title — starts empty and fills in as the proxy serves
  /// and read-aheads bytes.
  ValueListenable<List<CachedSpan>> cachedSpansFor(String itemId) =>
      _store.cachedSpansFor(itemId);

  // ── Request handling ──────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments[0] != 'm' || segments[1].isEmpty) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      await _serve(request, segments[1]);
    } catch (_) {
      // Client disconnects surface here too (broken pipe writing the
      // response) — never let one request crash the server.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serve(HttpRequest request, String itemId) async {
    final entry = await _store.open(itemId);
    await entry.touch();

    var total = entry.totalLength;
    if (total == null) {
      total = await _learnTotalLength(itemId, entry);
      if (total == null) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
    }

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
      await _streamRange(entry, itemId, start, end, response);
    } catch (_) {
      // Client aborted mid-response, or the upstream fetch failed after we'd
      // already committed headers — nothing more we can do for this request.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }

    // Fire-and-forget: keep filling the cache beyond what was just served.
    unawaited(_readAhead(entry, itemId, end, total));
  }

  /// Serves `[start, end)` to [response], reading present sub-ranges from the
  /// cache and fetching+forwarding+storing missing ones, in order.
  Future<void> _streamRange(
    CacheEntry entry,
    String itemId,
    int start,
    int end,
    HttpResponse response,
  ) async {
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
      if (segment.isPresent) {
        final data = await entry.read(segment.start, segment.end);
        response.add(data);
        await response.flush();
      } else {
        await _fetchAndForward(entry, itemId, segment.start, segment.end, response);
      }
    }
  }

  Future<void> _fetchAndForward(
    CacheEntry entry,
    String itemId,
    int start,
    int end,
    HttpResponse response,
  ) async {
    final upstream = await _fetchRemoteRange(itemId, start, end);
    try {
      var offset = start;
      await for (final chunk in upstream.response) {
        await entry.write(offset, chunk);
        offset += chunk.length;
        response.add(chunk);
        await response.flush();
      }
      await entry.flushMetadata();
    } finally {
      upstream.close();
    }
  }

  /// After a request is served, keeps fetching forward (bounded by
  /// [_readAheadWindow]) so upcoming playback hits cache. One pass per title
  /// at a time; on any fetch error the pass just stops early — the next
  /// on-demand request re-fetches whatever's still missing.
  Future<void> _readAhead(CacheEntry entry, String itemId, int from, int total) async {
    if (_readAheadInFlight.contains(itemId)) return;
    _readAheadInFlight.add(itemId);
    try {
      final windowEnd = (from + _readAheadWindow).clamp(0, total);
      if (windowEnd <= from) return;
      final gaps = entry.missingRanges(from, windowEnd);
      for (final gap in gaps) {
        var pos = gap.start;
        while (pos < gap.end) {
          final chunkEnd = (pos + _fetchChunkSize) > gap.end ? gap.end : pos + _fetchChunkSize;
          try {
            final upstream = await _fetchRemoteRange(itemId, pos, chunkEnd);
            try {
              var offset = pos;
              await for (final chunk in upstream.response) {
                await entry.write(offset, chunk);
                offset += chunk.length;
              }
            } finally {
              upstream.close();
            }
          } catch (_) {
            return; // give up this pass; on-demand fetches will fill gaps later
          }
          pos = chunkEnd;
        }
      }
      await entry.flushMetadata();
    } finally {
      _readAheadInFlight.remove(itemId);
    }
  }

  // ── Remote fetch (mint + re-mint on expiry) ───────────────────────────

  /// Probes the remote with a 1-byte ranged GET purely to learn the title's
  /// total length from `Content-Range`, and opportunistically caches that
  /// first byte since we already paid for the round trip.
  Future<int?> _learnTotalLength(String itemId, CacheEntry entry) async {
    final upstream = await _fetchRemoteRange(itemId, 0, 1);
    try {
      final res = upstream.response;
      if (res.statusCode != HttpStatus.ok &&
          res.statusCode != HttpStatus.partialContent) {
        return null;
      }
      final total = _totalFromHeaders(res);
      if (total == null) return null;
      entry.setTotalLength(total);
      final probeByte = await _drain(res);
      if (probeByte.isNotEmpty) await entry.write(0, probeByte);
      await entry.flushMetadata();
      return total;
    } finally {
      upstream.close();
    }
  }

  int? _totalFromHeaders(HttpClientResponse res) {
    final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    if (res.statusCode == HttpStatus.ok && res.contentLength >= 0) {
      return res.contentLength;
    }
    return null;
  }

  /// Fetches `[start, end)` from the remote signed URL, re-minting once if
  /// the signed token has expired (401/403) — the token embeds its own TTL
  /// server-side, so a long-idle title's stale link fails this way rather
  /// than at request time.
  Future<_Upstream> _fetchRemoteRange(String itemId, int start, int end) async {
    Future<_Upstream> attempt(String url) async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${end - 1}');
        final res = await req.close();
        return _Upstream(res, client);
      } catch (_) {
        client.close(force: true);
        rethrow;
      }
    }

    var signed = await _apiClient.nativeStreamUrl(itemId, purpose: 'stream');
    var upstream = await attempt(signed.url);
    if (upstream.response.statusCode == HttpStatus.unauthorized ||
        upstream.response.statusCode == HttpStatus.forbidden) {
      upstream.close();
      signed = await _apiClient.nativeStreamUrl(itemId, purpose: 'stream');
      upstream = await attempt(signed.url);
    }
    return upstream;
  }

  Future<List<int>> _drain(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
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
