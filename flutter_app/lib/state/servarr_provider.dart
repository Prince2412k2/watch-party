import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import 'providers.dart';

/// E9 — Servarr (radarr/sonarr/prowlarr/qbittorrent) state, built entirely on
/// the phase-0 `ApiClient.servarrGet/Post/Delete` passthroughs. Mirrors the web
/// reference (`app/client/src/pages/FindDownload.jsx` + `Downloads.jsx`):
/// search a title → grab-or-remove "request" → watch it land in the download
/// queue. No new ApiClient methods were needed — every route here is reached
/// through the existing generic passthroughs.

enum ServarrKind { movie, series }

extension ServarrKindX on ServarrKind {
  String get service => this == ServarrKind.movie ? 'radarr' : 'sonarr';
  String get label => this == ServarrKind.movie ? 'Movies' : 'Series';
}

/// A single search/lookup/popular result row. Radarr and Sonarr echo slightly
/// different fields (tmdbId vs tvdbId, no `network` on movies, …), so this
/// stays a tolerant wrapper over the raw JSON rather than two rigid models.
class ServarrTitle {
  ServarrTitle(this.raw);
  final Map<String, dynamic> raw;

  int? get tmdbId => raw['tmdbId'] as int?;
  int? get tvdbId => raw['tvdbId'] as int?;
  int? get id => raw['id'] as int?;
  String get title => (raw['title'] ?? '').toString();
  int? get year => raw['year'] as int?;
  String? get overview => raw['overview'] as String?;
  List<String> get genres =>
      ((raw['genres'] as List?) ?? const []).map((e) => e.toString()).toList();
  int? get runtime => raw['runtime'] as int?;
  String? get network => raw['network'] as String?;
  String? get status => raw['status'] as String?;
  int? get seasonCount => raw['seasonCount'] as int?;

  /// A lookup result only carries a numeric `id` once the title is already
  /// tracked in Radarr/Sonarr — that's the "already in the library" signal.
  bool get isAdded => id != null;

  String key(ServarrKind kind) =>
      kind == ServarrKind.movie ? 'm:${tmdbId ?? title}' : 's:${tvdbId ?? title}';

  /// Best poster URL out of `images`: a not-yet-added lookup only has a public
  /// `remoteUrl`; `url` (the instance-local path) only resolves once added.
  String? get posterUrl {
    final images = (raw['images'] as List?) ?? const [];
    if (images.isEmpty) return null;
    final list = images.cast<Map<String, dynamic>>();
    final poster = list.firstWhere(
      (i) => i['coverType'] == 'poster',
      orElse: () => list.first,
    );
    final url = poster['remoteUrl'] ?? poster['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// A single 0–10 rating out of the varied ratings shapes the catalog
  /// returns (`{value}`, or `{imdb:{value}}` / `{tmdb:{value}}`).
  double? get rating {
    final r = raw['ratings'];
    if (r is! Map) return null;
    final v = r['value'] ??
        (r['imdb'] is Map ? (r['imdb'] as Map)['value'] : null) ??
        (r['tmdb'] is Map ? (r['tmdb'] as Map)['value'] : null);
    if (v is num && v > 0) return v.toDouble();
    return null;
  }

  /// Series only — per-season rows for the season chooser.
  List<Map<String, dynamic>> get seasons =>
      ((raw['seasons'] as List?) ?? const []).cast<Map<String, dynamic>>();
}

/// Per-card UI state after a request. Mirrors the web's `outcomeToState`.
enum ServarrRequestState {
  idle,
  searching,
  grabbed,
  monitoring,
  noRelease,
  searchFailed,
  added,
  error,
}

ServarrRequestState _outcomeToState(String? outcome) => switch (outcome) {
      'grabbed' => ServarrRequestState.grabbed,
      'no_release' => ServarrRequestState.noRelease,
      'search_failed' => ServarrRequestState.searchFailed,
      'monitoring' => ServarrRequestState.monitoring,
      'exists' => ServarrRequestState.added,
      _ => ServarrRequestState.error,
    };

/// `GET /api/servarr/health` — which services are configured + reachable.
final servarrHealthProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final data = await api.servarrGet('health');
    return (data as Map).cast<String, dynamic>();
  } catch (_) {
    return const {'services': {}};
  }
});

/// True once `services.<service>` reports both `configured` and `reachable`.
bool servarrServiceReady(Map<String, dynamic> health, String service) {
  final s = (health['services'] as Map?)?[service] as Map?;
  return s?['configured'] == true && s?['reachable'] == true;
}

/// Quality profile / root folder / (series) language profile defaults for the
/// one-tap request path. Cached per-kind for the session (mirrors the web's
/// `metaCache`).
class ServarrMeta {
  ServarrMeta({
    required this.qualityProfileId,
    required this.rootFolderPath,
    this.languageProfileId,
  });
  final int qualityProfileId;
  final String rootFolderPath;
  final int? languageProfileId;
}

final servarrMetaProvider =
    FutureProvider.family.autoDispose<ServarrMeta?, ServarrKind>((ref, kind) async {
  final api = ref.watch(apiClientProvider);
  final service = kind.service;
  final profiles = await api.servarrGet('$service/quality-profiles') as List;
  final folders = await api.servarrGet('$service/root-folders') as List;
  if (profiles.isEmpty || folders.isEmpty) return null;
  int? langId;
  if (kind == ServarrKind.series) {
    final langs = await api.servarrGet('sonarr/language-profiles') as List;
    langId = langs.isNotEmpty ? langs.first['id'] as int? : null;
  }
  return ServarrMeta(
    qualityProfileId: profiles.first['id'] as int,
    rootFolderPath: folders.first['path'] as String,
    languageProfileId: langId,
  );
});

/// Discover ("popular") rail for the empty-search state.
final servarrPopularProvider =
    FutureProvider.family.autoDispose<List<ServarrTitle>, ServarrKind>((ref, kind) async {
  final api = ref.watch(apiClientProvider);
  final data = await api.servarrGet('${kind.service}/popular');
  final items = (data as Map)['items'] as List? ?? const [];
  return items.cast<Map<String, dynamic>>().map(ServarrTitle.new).toList();
});

class ServarrSearchState {
  const ServarrSearchState({
    this.kind = ServarrKind.movie,
    this.term = '',
    this.results = const [],
    this.loading = false,
    this.error,
    this.hasSearched = false,
    this.requestStates = const {},
  });

  final ServarrKind kind;
  final String term;
  final List<ServarrTitle> results;
  final bool loading;
  final String? error;
  final bool hasSearched;
  final Map<String, ServarrRequestState> requestStates;

  ServarrSearchState copyWith({
    ServarrKind? kind,
    String? term,
    List<ServarrTitle>? results,
    bool? loading,
    String? error,
    bool? hasSearched,
    Map<String, ServarrRequestState>? requestStates,
  }) {
    return ServarrSearchState(
      kind: kind ?? this.kind,
      term: term ?? this.term,
      results: results ?? this.results,
      loading: loading ?? this.loading,
      error: error,
      hasSearched: hasSearched ?? this.hasSearched,
      requestStates: requestStates ?? this.requestStates,
    );
  }
}

/// Search + one-tap "request" flow for the Find screen. A fresh keystroke or
/// tab flip cancels the in-flight search via a sequence guard so a slow
/// response can never clobber a newer one.
class ServarrSearchNotifier extends StateNotifier<ServarrSearchState> {
  ServarrSearchNotifier(this._ref) : super(const ServarrSearchState());

  final Ref _ref;
  Timer? _debounce;
  int _seq = 0;

  void setKind(ServarrKind kind) {
    if (kind == state.kind) return;
    _debounce?.cancel();
    _seq++;
    state = ServarrSearchState(kind: kind, term: state.term);
    if (state.term.trim().isNotEmpty) _search();
  }

  void setTerm(String term) {
    state = state.copyWith(term: term);
    _debounce?.cancel();
    if (term.trim().isEmpty) {
      _seq++;
      state = state.copyWith(
          results: [], hasSearched: false, loading: false, error: null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> submit() async {
    _debounce?.cancel();
    await _search();
  }

  Future<void> _search() async {
    final term = state.term.trim();
    if (term.isEmpty) return;
    final mySeq = ++_seq;
    state = state.copyWith(loading: true, error: null);
    try {
      final api = _ref.read(apiClientProvider);
      final data = await api
          .servarrGet('${state.kind.service}/search', query: {'term': term});
      if (mySeq != _seq) return;
      final results = (data as List)
          .cast<Map<String, dynamic>>()
          .map(ServarrTitle.new)
          .toList();
      state = state.copyWith(results: results, loading: false, hasSearched: true);
    } catch (_) {
      if (mySeq != _seq) return;
      state = state.copyWith(
        loading: false,
        hasSearched: true,
        error: 'Something went wrong. Try again.',
        results: const [],
      );
    }
  }

  ServarrRequestState stateFor(ServarrTitle t) {
    if (t.isAdded) return ServarrRequestState.added;
    return state.requestStates[t.key(state.kind)] ?? ServarrRequestState.idle;
  }

  void _setRequestState(String key, ServarrRequestState value) {
    state = state.copyWith(requestStates: {...state.requestStates, key: value});
  }

  /// Server-authoritative one-tap request: add (no auto-search) → live
  /// interactive release search → grab the best release, or remove the
  /// fileless entry if nothing is usable. See `app/server/servarr/index.js`
  /// `POST /radarr/request` / `POST /sonarr/request` for the exact contract.
  Future<void> request(ServarrTitle t) async {
    final key = t.key(state.kind);
    _setRequestState(key, ServarrRequestState.searching);
    try {
      final api = _ref.read(apiClientProvider);
      final meta = await _ref.read(servarrMetaProvider(state.kind).future);
      if (meta == null) throw Exception('meta unavailable');
      final body = state.kind == ServarrKind.movie
          ? {
              'movie': t.raw,
              'qualityProfileId': meta.qualityProfileId,
              'rootFolderPath': meta.rootFolderPath,
            }
          : {
              'series': t.raw,
              'qualityProfileId': meta.qualityProfileId,
              'languageProfileId': meta.languageProfileId,
              'rootFolderPath': meta.rootFolderPath,
              'monitor': true,
              'searchNow': true,
            };
      final res =
          await api.servarrPost('${state.kind.service}/request', body: body);
      final outcome = (res as Map)['outcome'] as String?;
      _setRequestState(key, _outcomeToState(outcome));
    } catch (_) {
      _setRequestState(key, ServarrRequestState.error);
    }
  }

  /// Removes a title already in the library (deletes files + excludes it).
  Future<void> remove(ServarrTitle t) async {
    final id = t.id;
    if (id == null) return;
    final path = state.kind == ServarrKind.movie
        ? 'radarr/movie/$id'
        : 'sonarr/series/$id';
    await _ref
        .read(apiClientProvider)
        .servarrDelete(path, query: const {'deleteFiles': 'true'});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final servarrSearchProvider =
    StateNotifierProvider.autoDispose<ServarrSearchNotifier, ServarrSearchState>(
  (ref) => ServarrSearchNotifier(ref),
);

// ── Download queue (radarr/sonarr acquisition queue + qBittorrent) ─────────
// Backs the QUEUE monitor screen — distinct from E8.2's native offline
// downloads. This tracks *active in-flight acquisition* (torrents/usenet the
// servarr stack is pulling down), not files already saved on-device.

/// One row of `GET /api/servarr/downloads/enriched` — a qBittorrent torrent
/// joined to its Radarr/Sonarr queue record (clean title/poster when matched).
class ServarrDownload {
  ServarrDownload(this.raw);
  final Map<String, dynamic> raw;

  String get hash => (raw['hash'] ?? '').toString();
  String get name =>
      (raw['displayTitle'] ?? raw['name'] ?? '').toString();
  String? get subtitle => raw['subtitle'] as String?;
  String? get posterUrl => raw['posterUrl'] as String?;
  String get torrentState => (raw['state'] ?? '').toString();
  double get progress => ((raw['progress'] ?? 0) as num).toDouble();
  int get size => ((raw['size'] ?? 0) as num).toInt();
  int get downloaded => ((raw['downloaded'] ?? 0) as num).toInt();
  int get dlspeed => ((raw['dlspeed'] ?? 0) as num).toInt();
  int get eta => ((raw['eta'] ?? 0) as num).toInt();
  int get numSeeds => ((raw['numSeeds'] ?? 0) as num).toInt();
  bool get matched => raw['matched'] == true;

  static const _pausedStates = {
    'pausedDL', 'pausedUP', 'stoppedDL', 'stoppedUP', 'paused',
  };
  bool get isPaused => _pausedStates.contains(torrentState);
  int get percent => (progress * 100).clamp(0, 100).round();
}

/// Polls the enriched download list every few seconds while listened to.
/// `autoDispose` + `ref.onDispose` stop the timer the moment the queue screen
/// is popped, so it never polls in the background.
final servarrDownloadsPollProvider =
    StreamProvider.autoDispose<List<ServarrDownload>>((ref) {
  final api = ref.watch(apiClientProvider);
  final controller = StreamController<List<ServarrDownload>>();

  Future<void> tick() async {
    try {
      final data = await api.servarrGet('downloads/enriched');
      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map(ServarrDownload.new)
          .toList();
      if (!controller.isClosed) controller.add(list);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  Timer? timer;
  controller.onListen = () {
    tick();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => tick());
  };
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// A Radarr/Sonarr queue record whose `status`/`trackedDownloadStatus` isn't a
/// plain "ok" — the "needs attention" list on the web Downloads page.
class ServarrArrQueueItem {
  ServarrArrQueueItem(this.raw);
  final Map<String, dynamic> raw;

  int get id => raw['id'] as int;
  String get service => (raw['service'] ?? '').toString();
  String get title => (raw['title'] ?? '').toString();
  bool get failing => raw['failing'] == true;
  String? get errorMessage => raw['errorMessage'] as String?;
  List<String> get statusMessages =>
      ((raw['statusMessages'] as List?) ?? const []).map((e) => e.toString()).toList();
}

/// Polls both `radarr/queue` and `sonarr/queue`, merges, and keeps only the
/// items flagged `failing` (stuck between grab and import).
final servarrFailingQueueProvider =
    StreamProvider.autoDispose<List<ServarrArrQueueItem>>((ref) {
  final api = ref.watch(apiClientProvider);
  final controller = StreamController<List<ServarrArrQueueItem>>();

  Future<void> tick() async {
    try {
      final results = await Future.wait<dynamic>([
        api.servarrGet('radarr/queue').catchError((_) => const []),
        api.servarrGet('sonarr/queue').catchError((_) => const []),
      ]);
      final merged = [
        ...(results[0] as List).cast<Map<String, dynamic>>(),
        ...(results[1] as List).cast<Map<String, dynamic>>(),
      ].map(ServarrArrQueueItem.new).where((q) => q.failing).toList();
      if (!controller.isClosed) controller.add(merged);
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  Timer? timer;
  controller.onListen = () {
    tick();
    timer = Timer.periodic(const Duration(seconds: 6), (_) => tick());
  };
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Mutations for the queue screen: pause/resume/delete a torrent, and drop a
/// stuck Radarr/Sonarr queue record.
class ServarrQueueActions {
  ServarrQueueActions(this._ref);
  final Ref _ref;
  ApiClient get _api => _ref.read(apiClientProvider);

  Future<void> pause(String hash) =>
      _api.servarrPost('qbittorrent/pause', body: {'hashes': hash});

  Future<void> resume(String hash) =>
      _api.servarrPost('qbittorrent/resume', body: {'hashes': hash});

  Future<void> deleteTorrent(String hash, {bool deleteFiles = false}) =>
      _api.servarrPost('qbittorrent/delete',
          body: {'hashes': hash, 'deleteFiles': deleteFiles});

  /// `blocklist` isn't reachable through the generic `servarrDelete` (it only
  /// forwards query params; the server reads it from the DELETE body) — left
  /// false here. See report: flagged as a minor ApiClient gap, not fixed
  /// silently since `servarrDelete`'s signature is a frozen contract.
  Future<void> removeQueueItem(ServarrArrQueueItem item) =>
      _api.servarrDelete('${item.service}/queue/${item.id}');
}

final servarrQueueActionsProvider =
    Provider.autoDispose<ServarrQueueActions>((ref) => ServarrQueueActions(ref));
