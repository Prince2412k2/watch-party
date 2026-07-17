import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import 'providers.dart';

/// E9 — Servarr (radarr/sonarr/prowlarr/qbittorrent) state, built entirely on
/// the `ApiClient.servarrGet/Post/Delete` passthroughs. Mirrors the redesigned
/// web reference (`app/client/src/pages/FindDownload.tsx` + `Downloads.tsx` +
/// `hooks/useTorrents.ts`): Discover browses two fixed discover rails (movies +
/// shows) and folds in the acquire flow — one-tap grab-or-remove "request",
/// release picker, season chooser, options + manual source — while the
/// Downloads screen watches the enriched download queue and the failing-queue.

enum ServarrKind { movie, series }

extension ServarrKindX on ServarrKind {
  String get service => this == ServarrKind.movie ? 'radarr' : 'sonarr';
  String get label => this == ServarrKind.movie ? 'Movies' : 'Shows';
}

/// A single discover/lookup result row. Radarr and Sonarr echo slightly
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
  String? get certification => raw['certification'] as String?;
  int? get seasonCount => raw['seasonCount'] as int?;

  /// A lookup result only carries a numeric `id` once the title is already
  /// tracked in Radarr/Sonarr — that's the "already in the library" signal.
  bool get isAdded => id != null;

  String key(ServarrKind kind) =>
      kind == ServarrKind.movie ? 'm:${tmdbId ?? title}' : 's:${tvdbId ?? title}';

  List<Map<String, dynamic>> get _images {
    final images = (raw['images'] as List?) ?? const [];
    return images.isEmpty ? const [] : images.cast<Map<String, dynamic>>();
  }

  /// Best poster URL out of `images`: a not-yet-added lookup only has a public
  /// `remoteUrl`; `url` (the instance-local path) only resolves once added.
  String? get posterUrl {
    final list = _images;
    if (list.isEmpty) return null;
    final poster = list.firstWhere(
      (i) => i['coverType'] == 'poster',
      orElse: () => list.first,
    );
    final url = poster['remoteUrl'] ?? poster['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// Wide fanart/backdrop for the detail hero; falls back to the poster.
  String? get backdropUrl {
    final list = _images;
    if (list.isEmpty) return null;
    final fan = list.firstWhere(
      (i) => i['coverType'] == 'fanart',
      orElse: () => list.firstWhere(
        (i) => i['coverType'] == 'banner',
        orElse: () => const <String, dynamic>{},
      ),
    );
    final url = fan['remoteUrl'] ?? fan['url'];
    if (url is String && url.isNotEmpty) return url;
    return posterUrl;
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

/// Full profile / root-folder / language lists for the options dialog (the
/// one-tap path only needs the first of each; this carries every option).
class ServarrProfiles {
  ServarrProfiles({
    required this.profiles,
    required this.rootFolders,
    required this.langProfiles,
  });
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> rootFolders;
  final List<Map<String, dynamic>> langProfiles;
}

final servarrProfilesProvider =
    FutureProvider.family.autoDispose<ServarrProfiles, ServarrKind>((ref, kind) async {
  final api = ref.watch(apiClientProvider);
  final service = kind.service;
  final profiles =
      (await api.servarrGet('$service/quality-profiles') as List)
          .cast<Map<String, dynamic>>();
  final folders =
      (await api.servarrGet('$service/root-folders') as List)
          .cast<Map<String, dynamic>>();
  var langs = <Map<String, dynamic>>[];
  if (kind == ServarrKind.series) {
    langs = (await api.servarrGet('sonarr/language-profiles') as List)
        .cast<Map<String, dynamic>>();
  }
  return ServarrProfiles(
    profiles: profiles,
    rootFolders: folders,
    langProfiles: langs,
  );
});

/// A discover rail's payload: the server's `source` (drives the heading —
/// `tmdb_trending` → "Trending this week", else "Discover") + the items.
class ServarrDiscover {
  ServarrDiscover({required this.source, required this.items});
  final String source;
  final List<ServarrTitle> items;
}

/// Discover rail: `GET /api/servarr/{service}/discover?page=1` → `{source,
/// items}`. Per-kind family so the movie and series rails load and degrade
/// independently (an empty/failed discover surfaces as a per-rail unavailable
/// state rather than a full-page error).
final servarrDiscoverProvider =
    FutureProvider.family.autoDispose<ServarrDiscover, ServarrKind>((ref, kind) async {
  final api = ref.watch(apiClientProvider);
  dynamic data;
  try {
    data = await api.servarrGet('${kind.service}/discover', query: {'page': 1});
    if (data is! Map || (data['items'] as List? ?? const []).isEmpty) {
      data = await api.servarrGet('${kind.service}/popular');
    }
  } catch (_) {
    data = await api.servarrGet('${kind.service}/popular');
  }
  final map = data as Map;
  final items = (map['items'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .map(ServarrTitle.new)
      .toList();
  return ServarrDiscover(
    source: (map['source'] as String?) ?? 'curated',
    items: items,
  );
});

final servarrSearchProvider = FutureProvider.family.autoDispose<
    List<ServarrTitle>, ({ServarrKind kind, String query})>((ref, request) async {
  final query = request.query.trim();
  if (query.isEmpty) return const [];
  final data = await ref.watch(apiClientProvider).servarrGet(
    '${request.kind.service}/search',
    query: {'term': query},
  );
  return (data as List)
      .cast<Map<String, dynamic>>()
      .map(ServarrTitle.new)
      .toList();
});

/// Per-title request state for the acquire flow, keyed by `keyOf(kind, item)`.
/// This is the correctness core of grab feedback (`outcomeToState`), shared by
/// Discover cards and the detail view so status stays consistent when
/// navigating in and out.
class ServarrRequests extends StateNotifier<Map<String, ServarrRequestState>> {
  ServarrRequests(this._ref) : super(const {});

  final Ref _ref;

  ServarrRequestState stateFor(ServarrTitle t, ServarrKind kind) {
    if (t.isAdded) return ServarrRequestState.added;
    return state[t.key(kind)] ?? ServarrRequestState.idle;
  }

  void _set(String key, ServarrRequestState value) =>
      state = {...state, key: value};

  /// Reflect an outcome an options dialog / season request already resolved.
  void applyOutcome(String key, String? outcome) =>
      _set(key, _outcomeToState(outcome));

  /// A release picker / manual grab hands the card straight to downloading —
  /// the live torrent match takes over the progress UI from here.
  void markGrabbed(String key) => _set(key, ServarrRequestState.grabbed);

  /// Server-authoritative one-tap request: add (no auto-search) → live
  /// interactive release search → grab the best release, or remove the
  /// fileless entry if nothing is usable. See `app/server/servarr/index.js`
  /// `POST /radarr/request` / `POST /sonarr/request` for the exact contract.
  Future<void> request(ServarrTitle t, ServarrKind kind) async {
    final key = t.key(kind);
    _set(key, ServarrRequestState.searching);
    try {
      final api = _ref.read(apiClientProvider);
      final meta = await _ref.read(servarrMetaProvider(kind).future);
      if (meta == null) throw Exception('meta unavailable');
      final body = kind == ServarrKind.movie
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
      final res = await api.servarrPost('${kind.service}/request', body: body);
      _set(key, _outcomeToState((res as Map)['outcome'] as String?));
    } catch (_) {
      _set(key, ServarrRequestState.error);
    }
  }

  /// Removes a title already in the library (deletes files + excludes it).
  Future<void> remove(ServarrTitle t, ServarrKind kind) async {
    final id = t.id;
    if (id == null) return;
    final path =
        kind == ServarrKind.movie ? 'radarr/movie/$id' : 'sonarr/series/$id';
    await _ref
        .read(apiClientProvider)
        .servarrDelete(path, query: const {'deleteFiles': 'true'});
  }
}

final servarrRequestsProvider =
    StateNotifierProvider<ServarrRequests, Map<String, ServarrRequestState>>(
  (ref) => ServarrRequests(ref),
);

// ── Torrent state mapping (shared with the web `format.ts` `stateInfo`) ─────

/// Friendly label + paused-ness for a qBittorrent state string. qBittorrent 5.x
/// renamed `paused*` → `stopped*`; both are kept so a version bump can't
/// silently mislabel.
class TorrentStateInfo {
  const TorrentStateInfo(this.label, this.paused);
  final String label;
  final bool paused;
}

TorrentStateInfo torrentStateInfo(String? state) => switch (state) {
      'downloading' ||
      'forcedDL' ||
      'metaDL' ||
      'checkingDL' ||
      'allocating' =>
        const TorrentStateInfo('Downloading', false),
      'uploading' ||
      'forcedUP' ||
      'checkingUP' =>
        const TorrentStateInfo('Finishing up', false),
      'stalledDL' => const TorrentStateInfo('Waiting', false),
      'stalledUP' => const TorrentStateInfo('Finishing up', false),
      'queuedDL' ||
      'queuedUP' ||
      'checkingResumeData' =>
        const TorrentStateInfo('Queued', false),
      'pausedDL' || 'stoppedDL' => const TorrentStateInfo('Paused', true),
      'pausedUP' || 'stoppedUP' => const TorrentStateInfo('Completed', true),
      'error' || 'missingFiles' => const TorrentStateInfo('Error', true),
      _ => TorrentStateInfo(
          state == null || state.isEmpty ? 'Unknown' : state, false),
    };

/// "Actively downloading" — excludes seeding/completed/paused/error so the
/// aggregate "N active" count agrees with the web `DOWNLOADING_STATES` set.
const _downloadingStates = {
  'downloading', 'forcedDL', 'metaDL', 'forcedMetaDL',
  'stalledDL', 'queuedDL', 'checkingDL', 'allocating', 'checkingResumeData',
};

String _normTitle(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Best-effort link between a title and its active download — the normalized
/// title as a substring of the normalized torrent scene name.
ServarrDownload? matchTorrent(String title, List<ServarrDownload>? torrents) {
  final n = _normTitle(title);
  if (n.length < 2 || torrents == null) return null;
  for (final t in torrents) {
    if (_normTitle(t.sceneName).contains(n)) return t;
  }
  return null;
}

// ── Download queue (radarr/sonarr acquisition queue + qBittorrent) ─────────

/// One row of `GET /api/servarr/downloads/enriched` — a qBittorrent torrent
/// joined to its Radarr/Sonarr queue record (clean title/poster when matched).
class ServarrDownload {
  ServarrDownload(this.raw);
  final Map<String, dynamic> raw;

  String get hash => (raw['hash'] ?? '').toString();

  /// The raw scene release name (matched against titles for the live-download
  /// overlay); distinct from the clean [name].
  String get sceneName => (raw['name'] ?? '').toString();
  String get name => (raw['displayTitle'] ?? raw['name'] ?? '').toString();
  String? get subtitle => raw['subtitle'] as String?;
  String? get posterUrl => raw['posterUrl'] as String?;
  String? get kind => raw['kind'] as String?;
  String get torrentState => (raw['state'] ?? '').toString();
  double get progress => ((raw['progress'] ?? 0) as num).toDouble();
  int get size => ((raw['size'] ?? 0) as num).toInt();
  int get downloaded => ((raw['downloaded'] ?? 0) as num).toInt();
  int get dlspeed => ((raw['dlspeed'] ?? 0) as num).toInt();
  int get upspeed => ((raw['upspeed'] ?? 0) as num).toInt();
  int get eta => ((raw['eta'] ?? 0) as num).toInt();
  int get numSeeds => ((raw['numSeeds'] ?? 0) as num).toInt();
  int get numLeechs => ((raw['numLeechs'] ?? 0) as num).toInt();
  bool get matched => raw['matched'] == true;

  TorrentStateInfo get stateInfo => torrentStateInfo(torrentState);
  bool get isPaused => stateInfo.paused;
  bool get isActive => _downloadingStates.contains(torrentState);
  int get percent => (progress * 100).clamp(0, 100).round();
}

/// A poll snapshot: keeps the last-good [list] on a failed tick and flags a
/// subtle [loadError] (reconnecting) instead of dropping the whole list, so a
/// single dropped poll never clears the grid. [loaded] is false until the first
/// tick resolves.
class ServarrDownloadsSnapshot {
  const ServarrDownloadsSnapshot({
    this.list = const [],
    this.loadError = false,
    this.loaded = false,
  });
  final List<ServarrDownload> list;
  final bool loadError;
  final bool loaded;

  int get activeCount => list.where((d) => d.isActive).length;
  int get totalDlspeed => list.fold(0, (a, d) => a + d.dlspeed);
  int get totalUpspeed => list.fold(0, (a, d) => a + d.upspeed);

  ServarrDownloadsSnapshot copyWith({
    List<ServarrDownload>? list,
    bool? loadError,
    bool? loaded,
  }) =>
      ServarrDownloadsSnapshot(
        list: list ?? this.list,
        loadError: loadError ?? this.loadError,
        loaded: loaded ?? this.loaded,
      );
}

/// Polls the enriched download list every 4s while listened to. Shared by the
/// Downloads grid + detail and the Discover cards' live-download overlay.
/// `autoDispose` + `ref.onDispose` stop the timer the moment the last listener
/// is gone, so it never polls in the background.
final servarrDownloadsPollProvider =
    StreamProvider.autoDispose<ServarrDownloadsSnapshot>((ref) {
  final api = ref.watch(apiClientProvider);
  final controller = StreamController<ServarrDownloadsSnapshot>();
  var snapshot = const ServarrDownloadsSnapshot();

  Future<void> tick() async {
    try {
      final data = await api.servarrGet('downloads/enriched');
      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map(ServarrDownload.new)
          .toList();
      snapshot = ServarrDownloadsSnapshot(list: list, loaded: true);
      if (!controller.isClosed) controller.add(snapshot);
    } catch (_) {
      // Keep the last good list; surface a subtle reconnect flag.
      snapshot = snapshot.copyWith(loadError: true, loaded: true);
      if (!controller.isClosed) controller.add(snapshot);
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

/// Rich metadata for a single active download (`GET
/// /api/servarr/downloads/:hash/detail`). Falls back silently to the live
/// enriched fields if the lookup can't resolve.
class ServarrDownloadDetail {
  ServarrDownloadDetail(this.raw);
  final Map<String, dynamic> raw;

  String? get kind => raw['kind'] as String?;
  String? get title => raw['title'] as String?;
  String? get subtitle => raw['subtitle'] as String?;
  String? get posterUrl => raw['posterUrl'] as String?;
  String? get overview => raw['overview'] as String?;
  List<String> get genres =>
      ((raw['genres'] as List?) ?? const []).map((e) => e.toString()).toList();
  double? get rating => (raw['rating'] as num?)?.toDouble();
  int? get runtime => (raw['runtime'] as num?)?.toInt();
  String? get year => raw['year']?.toString();
  String? get certification => raw['certification'] as String?;
  String? get network => raw['network'] as String?;
  String? get status => raw['status'] as String?;
}

final servarrDownloadDetailProvider =
    FutureProvider.family.autoDispose<ServarrDownloadDetail?, String>((ref, hash) async {
  final api = ref.watch(apiClientProvider);
  try {
    final data =
        await api.servarrGet('downloads/${Uri.encodeComponent(hash)}/detail');
    return ServarrDownloadDetail((data as Map).cast<String, dynamic>());
  } catch (_) {
    return null;
  }
});

/// A Radarr/Sonarr queue record whose status isn't a plain "ok" — the "needs
/// attention" list on the Downloads page.
class ServarrArrQueueItem {
  ServarrArrQueueItem(this.raw);
  final Map<String, dynamic> raw;

  int get id => raw['id'] as int;
  String get service => (raw['service'] ?? '').toString();
  String get title => (raw['title'] ?? '').toString();
  bool get failing => raw['failing'] == true;
  String? get errorMessage => raw['errorMessage'] as String?;
  String? get indexer => raw['indexer'] as String?;
  int get size => ((raw['size'] ?? 0) as num).toInt();
  List<String> get statusMessages =>
      ((raw['statusMessages'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();

  /// One line per status message, or the error message, or a placeholder.
  List<String> get reasons {
    if (statusMessages.isNotEmpty) return statusMessages;
    if (errorMessage != null && errorMessage!.isNotEmpty) return [errorMessage!];
    return const ['No reason given.'];
  }
}

/// Failing-queue snapshot — like [ServarrDownloadsSnapshot], keeps the last-good
/// list on a failed tick and flags [loadError].
class ServarrFailingSnapshot {
  const ServarrFailingSnapshot({
    this.items = const [],
    this.loadError = false,
    this.loaded = false,
  });
  final List<ServarrArrQueueItem> items;
  final bool loadError;
  final bool loaded;

  ServarrFailingSnapshot copyWith({
    List<ServarrArrQueueItem>? items,
    bool? loadError,
    bool? loaded,
  }) =>
      ServarrFailingSnapshot(
        items: items ?? this.items,
        loadError: loadError ?? this.loadError,
        loaded: loaded ?? this.loaded,
      );
}

/// Polls both `radarr/queue` and `sonarr/queue` every 6s, merges, and keeps only
/// the items flagged `failing` (stuck between grab and import).
final servarrFailingQueueProvider =
    StreamProvider.autoDispose<ServarrFailingSnapshot>((ref) {
  final api = ref.watch(apiClientProvider);
  final controller = StreamController<ServarrFailingSnapshot>();
  var snapshot = const ServarrFailingSnapshot();

  Future<void> tick() async {
    try {
      final results = await Future.wait<dynamic>([
        api.servarrGet('radarr/queue').then<dynamic>((v) => v).catchError((_) => null),
        api.servarrGet('sonarr/queue').then<dynamic>((v) => v).catchError((_) => null),
      ]);
      if (results[0] == null && results[1] == null) {
        snapshot = snapshot.copyWith(loadError: true, loaded: true);
        if (!controller.isClosed) controller.add(snapshot);
        return;
      }
      final merged = [
        ...((results[0] as List?) ?? const []).cast<Map<String, dynamic>>(),
        ...((results[1] as List?) ?? const []).cast<Map<String, dynamic>>(),
      ].map(ServarrArrQueueItem.new).where((q) => q.failing).toList();
      snapshot = ServarrFailingSnapshot(items: merged, loaded: true);
      if (!controller.isClosed) controller.add(snapshot);
    } catch (_) {
      snapshot = snapshot.copyWith(loadError: true, loaded: true);
      if (!controller.isClosed) controller.add(snapshot);
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

/// Mutations for the Downloads screen: pause/resume/delete a torrent, and drop a
/// stuck Radarr/Sonarr queue record (optionally blocklisting the release).
class ServarrQueueActions {
  ServarrQueueActions(this._ref);
  final Ref _ref;
  ApiClient get _api => _ref.read(apiClientProvider);

  Future<void> pause(String hash) =>
      _api.servarrPost('qbittorrent/pause', body: {'hashes': hash});

  Future<void> resume(String hash) =>
      _api.servarrPost('qbittorrent/resume', body: {'hashes': hash});

  /// Default `deleteFiles:false` — the delete dialog's "also delete files"
  /// toggle drives it (matches the web, which defaults the toggle off).
  Future<void> deleteTorrent(String hash, {bool deleteFiles = false}) =>
      _api.servarrPost('qbittorrent/delete',
          body: {'hashes': hash, 'deleteFiles': deleteFiles});

  /// Drop a stuck queue item. `blocklist:true` also blocks the release from
  /// being grabbed again (the server reads it from the DELETE body).
  Future<void> removeQueueItem(ServarrArrQueueItem item,
          {bool blocklist = false}) =>
      _api.servarrDelete('${item.service}/queue/${item.id}',
          body: {'blocklist': blocklist});
}

final servarrQueueActionsProvider =
    Provider.autoDispose<ServarrQueueActions>((ref) => ServarrQueueActions(ref));

// ── Display formatters (shared with the web `format.ts`) ────────────────────

/// Raw bytes → "12.4 MB". "—" for missing/zero.
String fmtSize(num? bytes) {
  if (bytes == null || !bytes.isFinite || bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return '${n < 10 && i > 0 ? n.toStringAsFixed(1) : n.round()} ${units[i]}';
}

/// Bytes-per-second → "12.4 MB/s". "0 B/s" for missing/zero.
String fmtSpeed(num? bps) {
  if (bps == null || !bps.isFinite || bps <= 0) return '0 B/s';
  return '${fmtSize(bps)}/s';
}

/// Seconds → "1h 2m". "∞" for the client's unknown sentinel, "—" for 0.
String fmtEta(num? secs) {
  if (secs == null || !secs.isFinite || secs < 0 || secs >= 8640000) return '∞';
  if (secs == 0) return '—';
  final s = secs.toInt();
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${sec}s';
}

/// Runtime minutes → "1h 42m".
String? fmtRuntimeFromMinutes(num? mins) {
  if (mins == null || !mins.isFinite || mins <= 0) return null;
  final m = mins.toInt();
  final h = m ~/ 60;
  return h > 0 ? '${h}h ${m % 60}m' : '${m}m';
}
