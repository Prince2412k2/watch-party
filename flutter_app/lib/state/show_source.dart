import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import 'library_provider.dart';
import 'providers.dart';
import 'servarr_provider.dart';

/// "One show stage, two sources"
/// (docs/specs/2026-07-31-show-discovery-download.md): a Jellyfin library
/// series and a Sonarr/TMDB Discover series are read into the same
/// [ShowStageInfo] / [ShowEpisode] shapes, so the show-stage widget never
/// branches on where the data came from — only the primary action does.
/// [showDownloadProvider] is the unattended whole-show/per-season download
/// loop that FR-018 requires never gets stuck: every future it awaits either
/// resolves or is caught and turned into a terminal [SeasonOutcome].

enum ShowSourceKind { library, discover }

/// Identifies a series regardless of source: a Jellyfin item id, or the
/// Discover series' tvdbId (as a string, since Sonarr's lookup keys on it).
class ShowRef {
  const ShowRef({required this.kind, required this.id});
  final ShowSourceKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ShowRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// One season of one show — the family key for [showEpisodesProvider].
class ShowEpisodesRef {
  const ShowEpisodesRef({required this.show, required this.seasonNumber});
  final ShowRef show;
  final int seasonNumber;

  @override
  bool operator ==(Object other) =>
      other is ShowEpisodesRef &&
      other.show == show &&
      other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(show, seasonNumber);
}

/// One episode row. Deliberately mirrors the server's `shapeEpisode` /
/// `tmdbSeasonEpisodes` shapes (app/server/servarr/index.js,
/// app/server/servarr/tmdb.js) so a Sonarr-sourced and TMDB-sourced episode
/// need no separate UI branch — only [episodeId] and [hasFile] carry more
/// truth when the source is Sonarr.
class ShowEpisode {
  const ShowEpisode({
    this.episodeId,
    this.jellyfinId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.name,
    this.overview,
    this.still,
    this.airDate,
    this.runtime,
    this.rating,
    required this.hasFile,
  });

  final int? episodeId;
  final String? jellyfinId;
  final int seasonNumber;
  final int episodeNumber;
  final String? name;
  final String? overview;
  final String? still;
  final String? airDate;
  final int? runtime;
  final double? rating;
  final bool hasFile;
}

/// Everything the show stage needs above the episode row — series copy, art,
/// and enough Sonarr/Jellyfin identity for the download actions to target the
/// right place without a second lookup.
class ShowStageInfo {
  const ShowStageInfo({
    required this.title,
    this.genres = const [],
    this.overview,
    this.certification,
    this.network,
    this.backdropUrl,
    this.posterUrl,
    this.year,
    this.runtime,
    this.rating,
    this.seasonNumbers = const [],
    this.sonarrSeriesId,
    this.sonarrSeriesRaw,
    this.jellyfinSeriesId,
  });

  final String title;
  final List<String> genres;
  final String? overview;
  final String? certification;
  final String? network;
  final String? backdropUrl;
  final String? posterUrl;
  final int? year;
  final int? runtime;
  final double? rating;
  final List<int> seasonNumbers;
  final int? sonarrSeriesId;
  final Map<String, dynamic>? sonarrSeriesRaw;
  final String? jellyfinSeriesId;
}

/// Which route an all-seasons pass took for one season (server's
/// `sonarr/auto-season` `route` field).
enum SeasonRoute { season, episodes, none }

class SeasonOutcome {
  const SeasonOutcome({
    required this.seasonNumber,
    required this.route,
    this.grabbed = 0,
    this.missing = const [],
    this.error,
  });

  final int seasonNumber;
  final SeasonRoute route;
  final int grabbed;
  final List<int> missing;

  /// Set only when the season failed for a reason other than "searched fine,
  /// found nothing" — a season the server itself reports as `route: 'none'`
  /// (no pack, no episode releases) is a legitimate empty result, not this.
  final String? error;
}

// ── Show info ────────────────────────────────────────────────────────────

/// Ticks (Jellyfin's 100ns unit) → whole minutes.
int? _runtimeMinutes(int? ticks) =>
    ticks == null || ticks <= 0 ? null : (ticks / 600000000).round();

/// Ascending season numbers with Specials (0) moved to the end.
List<int> _orderSeasons(Iterable<int> raw) {
  final nums = raw.toSet().toList()..sort();
  if (nums.isNotEmpty && nums.first == 0) {
    nums
      ..removeAt(0)
      ..add(0);
  }
  return nums;
}

/// Case-insensitive `Tvdb` provider id off a Jellyfin item's `ProviderIds`
/// (keys have been seen as `Tvdb`, and plugin variance means the casing isn't
/// worth trusting).
int? _tvdbIdFrom(Map<String, String> providerIds) {
  for (final entry in providerIds.entries) {
    if (entry.key.toLowerCase() == 'tvdb') return int.tryParse(entry.value);
  }
  return null;
}

/// Sonarr's series lookup by tvdbId (`sonarr/search?term=tvdb:<id>`,
/// `shapeSeriesLookup` server-side) — the best match for [tvdbId], or null if
/// nothing came back. Shared by the Discover path (which requires a hit) and
/// the library identity resolution below (which tolerates a miss).
Future<Map<String, dynamic>?> _sonarrLookupByTvdb(
  ApiClient api,
  int tvdbId,
) async {
  final data = await api.servarrGet(
    'sonarr/search',
    query: {'term': 'tvdb:$tvdbId'},
  );
  final list = (data is List ? data : const []).cast<Map<String, dynamic>>();
  if (list.isEmpty) return null;
  return list.firstWhere(
    (m) => (m['tvdbId'] as num?)?.toInt() == tvdbId,
    orElse: () => list.first,
  );
}

/// Best-effort Sonarr identity for a library series (US-1: episode-level
/// downloads need this for a series ALREADY in the library, not just
/// Discover). Resolved off the Jellyfin item's Tvdb provider id: first
/// against Sonarr's own library (already added → a real `seriesId`), else
/// against the lookup (not yet added → a raw payload the picker can shell
/// the series in from, same as the Discover path). Every failure mode —
/// no Tvdb id, Sonarr unconfigured, unreachable, a 503 — degrades to
/// `(null, null)` rather than throwing; this must never be why
/// [showInfoProvider] fails for a library series.
Future<(int?, Map<String, dynamic>?)> _librarySonarrIdentity(
  ApiClient api,
  Map<String, String> providerIds,
) async {
  final tvdbId = _tvdbIdFrom(providerIds);
  if (tvdbId == null) return (null, null);

  try {
    final library = await api.servarrGet('sonarr/series');
    final rows = (library is List ? library : const [])
        .cast<Map<String, dynamic>>();
    for (final row in rows) {
      if ((row['tvdbId'] as num?)?.toInt() == tvdbId) {
        return ((row['id'] as num?)?.toInt(), null);
      }
    }
  } catch (_) {
    // Sonarr unconfigured/unreachable — fall through to the lookup below.
  }

  try {
    return (null, await _sonarrLookupByTvdb(api, tvdbId));
  } catch (_) {
    return (null, null);
  }
}

/// A library series' stage info — reuses [itemDetailProvider], the same
/// Jellyfin item-detail path `detail_stage.dart` already reads, plus
/// `children()` for the season list (no new HTTP path). The Sonarr identity
/// is resolved alongside it (see [_librarySonarrIdentity]) so the download
/// actions have something to target even though this series was reached
/// through the library rather than Discover.
Future<ShowStageInfo> _libraryShowInfo(
  Ref ref,
  ApiClient api,
  String seriesId,
) async {
  final item = await ref.watch(itemDetailProvider(seriesId).future);
  final seasons = await api.children(seriesId);
  final seasonNumbers = _orderSeasons(
    seasons.map((s) => s.indexNumber).whereType<int>(),
  );
  final (sonarrSeriesId, sonarrSeriesRaw) = await _librarySonarrIdentity(
    api,
    item.providerIds,
  );
  return ShowStageInfo(
    title: item.name,
    genres: item.genres,
    overview: item.overview,
    certification: item.officialRating,
    backdropUrl: api.imageUrl(seriesId, type: ImageType.backdrop),
    posterUrl: api.imageUrl(seriesId),
    year: item.productionYear,
    runtime: _runtimeMinutes(item.runTimeTicks),
    rating: item.communityRating,
    seasonNumbers: seasonNumbers,
    sonarrSeriesId: sonarrSeriesId,
    sonarrSeriesRaw: sonarrSeriesRaw,
    jellyfinSeriesId: seriesId,
  );
}

/// A Discover series' stage info, off the same Sonarr lookup the Discover
/// screens already fetch. [ServarrTitle] is reused as-is for the poster/
/// backdrop/rating extraction so this doesn't reinvent that parsing.
Future<ShowStageInfo> _discoverShowInfo(ApiClient api, String tvdbIdStr) async {
  final tvdbId = int.tryParse(tvdbIdStr);
  if (tvdbId == null) {
    throw ApiException(
      'showInfo',
      400,
      'invalid Discover show id "$tvdbIdStr"',
    );
  }
  final raw = await _sonarrLookupByTvdb(api, tvdbId);
  if (raw == null) {
    throw ApiException('showInfo', 404, 'no series found for tvdbId $tvdbId');
  }
  final title = ServarrTitle(raw);
  return ShowStageInfo(
    title: title.title,
    genres: title.genres,
    overview: title.overview,
    certification: title.certification,
    network: title.network,
    backdropUrl: title.backdropUrl,
    posterUrl: title.posterUrl,
    year: title.year,
    runtime: title.runtime,
    rating: title.rating,
    seasonNumbers: _orderSeasons(
      title.seasons.map((s) => (s['seasonNumber'] as num?)?.toInt() ?? 0),
    ),
    sonarrSeriesId: title.id,
    sonarrSeriesRaw: raw,
  );
}

final showInfoProvider = FutureProvider.family<ShowStageInfo, ShowRef>((
  ref,
  show,
) async {
  final api = ref.watch(apiClientProvider);
  return show.kind == ShowSourceKind.library
      ? _libraryShowInfo(ref, api, show.id)
      : _discoverShowInfo(api, show.id);
});

// ── Episodes ─────────────────────────────────────────────────────────────

/// A relative `/api/...` path (the server's servarr image proxy sometimes
/// answers with one, e.g. Sonarr screenshots without a public `remoteUrl`)
/// needs the API origin prefixed; TMDB stills and Sonarr `remoteUrl`s already
/// arrive absolute.
String? _absoluteImage(ApiClient api, String? url) {
  if (url == null || url.isEmpty) return null;
  return url.startsWith('/') ? '${api.baseUrl}$url' : url;
}

/// A library season's episodes — reuses [seriesSeasonsProvider], the same
/// season+episode fetch the existing episode dock reads, rather than a new
/// route. `hasFile` is truthful: a Jellyfin child row with no media source is
/// a metadata stub, not a downloaded episode.
Future<List<ShowEpisode>> _libraryEpisodes(
  Ref ref,
  ApiClient api,
  ShowEpisodesRef key,
) async {
  final seasons = await ref.watch(seriesSeasonsProvider(key.show.id).future);
  SeasonEpisodes? row;
  for (final candidate in seasons) {
    if ((candidate.season.indexNumber ?? 0) == key.seasonNumber) {
      row = candidate;
      break;
    }
  }
  if (row == null) return const [];
  return row.episodes
      .map(
        (e) => ShowEpisode(
          jellyfinId: e.id,
          seasonNumber: key.seasonNumber,
          episodeNumber: e.indexNumber ?? 0,
          name: e.name.isEmpty ? null : e.name,
          overview: e.overview,
          // Primary, not Thumb. Jellyfin puts an episode's still on its
          // PRIMARY image; Thumb is a series/season-level artwork type that
          // episodes generally do not carry. Asking for Thumb 404'd on every
          // episode — no stills in the app at all, and a flood of "Artwork
          // request failed: HTTP 404" behind it. The web client has always
          // asked for Primary, which is why its stills appear.
          still: api.imageUrl(e.id, type: ImageType.primary),
          airDate: e.premiereDate,
          runtime: _runtimeMinutes(e.runTimeTicks),
          rating: e.communityRating,
          hasFile: e.mediaSources.isNotEmpty,
        ),
      )
      .toList();
}

/// A Discover season's episodes, via `GET /api/servarr/sonarr/episodes` —
/// `source: 'sonarr'` and `source: 'tmdb'` share a response shape server-side,
/// so no branching is needed here beyond which id to send.
Future<List<ShowEpisode>> _discoverEpisodes(
  Ref ref,
  ApiClient api,
  ShowEpisodesRef key,
) async {
  final info = await ref.watch(showInfoProvider(key.show).future);
  final query = <String, dynamic>{'seasonNumber': key.seasonNumber};
  if (info.sonarrSeriesId != null) {
    query['seriesId'] = info.sonarrSeriesId;
  } else {
    final tmdbId = info.sonarrSeriesRaw?['tmdbId'];
    if (tmdbId != null) {
      query['tmdbId'] = tmdbId;
    } else {
      final tvdbId = int.tryParse(key.show.id);
      if (tvdbId != null) query['tvdbId'] = tvdbId;
    }
  }
  final data = await api.servarrGet('sonarr/episodes', query: query) as Map;
  final episodes = (data['episodes'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  return episodes
      .map(
        (e) => ShowEpisode(
          episodeId: (e['episodeId'] as num?)?.toInt(),
          seasonNumber: key.seasonNumber,
          episodeNumber: (e['episodeNumber'] as num?)?.toInt() ?? 0,
          name: e['name'] as String?,
          overview: e['overview'] as String?,
          still: _absoluteImage(api, e['still'] as String?),
          airDate: e['airDate'] as String?,
          runtime: (e['runtime'] as num?)?.toInt(),
          rating: (e['rating'] as num?)?.toDouble(),
          hasFile: e['hasFile'] == true,
        ),
      )
      .toList();
}

final showEpisodesProvider =
    FutureProvider.family<List<ShowEpisode>, ShowEpisodesRef>((ref, key) async {
      final api = ref.watch(apiClientProvider);
      return key.show.kind == ShowSourceKind.library
          ? _libraryEpisodes(ref, api, key)
          : _discoverEpisodes(ref, api, key);
    });

// ── Whole-show / per-season download ────────────────────────────────────

/// Which season an all-seasons run is currently on, and the outcomes for the
/// seasons already finished — enough for the UI to show progress without
/// polling anything itself.
class ShowDownloadProgress {
  const ShowDownloadProgress({
    this.running = false,
    this.inFlightSeason,
    this.outcomes = const [],
  });

  final bool running;
  final int? inFlightSeason;
  final List<SeasonOutcome> outcomes;

  ShowDownloadProgress copyWith({
    bool? running,
    int? inFlightSeason,
    bool clearInFlight = false,
    List<SeasonOutcome>? outcomes,
  }) => ShowDownloadProgress(
    running: running ?? this.running,
    inFlightSeason: clearInFlight
        ? null
        : (inFlightSeason ?? this.inFlightSeason),
    outcomes: outcomes ?? this.outcomes,
  );
}

/// Drives `sonarr/auto-season` for one season or, for all-seasons, the whole
/// series — sequentially, since each call can run a live indexer search
/// server-side (~45s) and six of those in parallel would hammer the indexers.
class ShowDownloadNotifier extends StateNotifier<ShowDownloadProgress> {
  ShowDownloadNotifier(this._ref) : super(const ShowDownloadProgress());
  final Ref _ref;

  /// Recovers the [ShowRef] a [ShowStageInfo] was built from, so all-seasons
  /// can check a season's completeness (via [showEpisodesProvider]) before
  /// spending a network round trip on a season that's already done.
  ShowRef? _refFor(ShowStageInfo info) {
    if (info.jellyfinSeriesId != null) {
      return ShowRef(kind: ShowSourceKind.library, id: info.jellyfinSeriesId!);
    }
    final tvdbId = info.sonarrSeriesRaw?['tvdbId'];
    return tvdbId == null
        ? null
        : ShowRef(kind: ShowSourceKind.discover, id: '$tvdbId');
  }

  Future<bool> _seasonComplete(ShowStageInfo info, int seasonNumber) async {
    final show = _refFor(info);
    if (show == null) return false;
    try {
      final episodes = await _ref.read(
        showEpisodesProvider(
          ShowEpisodesRef(show: show, seasonNumber: seasonNumber),
        ).future,
      );
      return episodes.isNotEmpty && episodes.every((e) => e.hasFile);
    } catch (_) {
      // Unknown beats wrongly-skipped: treat as incomplete so it's attempted.
      return false;
    }
  }

  /// POSTs `sonarr/auto-season` for one season, either against an existing
  /// Sonarr series or a lookup `series` + the default
  /// quality/root-folder/language profile for a series not yet added.
  Future<SeasonOutcome> autoSeason(ShowStageInfo info, int seasonNumber) async {
    final api = _ref.read(apiClientProvider);
    final body = <String, dynamic>{'seasonNumber': seasonNumber};
    if (info.sonarrSeriesId != null) {
      body['seriesId'] = info.sonarrSeriesId;
    } else {
      final raw = info.sonarrSeriesRaw;
      if (raw == null) {
        throw Exception('"${info.title}" has no Sonarr data to add it from');
      }
      final meta = await _ref.read(
        servarrMetaProvider(ServarrKind.series).future,
      );
      if (meta == null) {
        throw Exception('Servarr quality profile / root folder unavailable');
      }
      body['series'] = raw;
      body['qualityProfileId'] = meta.qualityProfileId;
      body['languageProfileId'] = meta.languageProfileId;
      body['rootFolderPath'] = meta.rootFolderPath;
    }

    final res = await api.servarrPost('sonarr/auto-season', body: body) as Map;
    return SeasonOutcome(
      seasonNumber: (res['seasonNumber'] as num?)?.toInt() ?? seasonNumber,
      route: switch (res['route']) {
        'season' => SeasonRoute.season,
        'episodes' => SeasonRoute.episodes,
        _ => SeasonRoute.none,
      },
      grabbed: (res['grabbed'] as num?)?.toInt() ?? 0,
      missing: ((res['missing'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }

  /// Runs [autoSeason] over every season, in order, skipping ones already
  /// fully downloaded. A season that throws is recorded as [SeasonRoute.none]
  /// with [SeasonOutcome.error] set to the reason, rather than aborting the
  /// run — one indexer hiccup or a dropped connection shouldn't stop the rest
  /// of the series. [error] is what keeps this honest per FR-018: a season
  /// the server searched and came up empty on is `route: none` with `error:
  /// null`; a season that couldn't even be searched carries the reason, so
  /// the UI never conflates "nothing found" with "something went wrong".
  Future<List<SeasonOutcome>> autoAllSeasons(ShowStageInfo info) async {
    state = const ShowDownloadProgress(running: true);
    final outcomes = <SeasonOutcome>[];
    try {
      for (final seasonNumber in info.seasonNumbers) {
        if (await _seasonComplete(info, seasonNumber)) continue;
        state = state.copyWith(inFlightSeason: seasonNumber);
        try {
          outcomes.add(await autoSeason(info, seasonNumber));
        } catch (e) {
          outcomes.add(
            SeasonOutcome(
              seasonNumber: seasonNumber,
              route: SeasonRoute.none,
              error: e is ApiException ? e.message : e.toString(),
            ),
          );
        }
        state = state.copyWith(outcomes: List.unmodifiable(outcomes));
      }
      return outcomes;
    } finally {
      state = state.copyWith(running: false, clearInFlight: true);
    }
  }
}

final showDownloadProvider =
    StateNotifierProvider<ShowDownloadNotifier, ShowDownloadProgress>(
      (ref) => ShowDownloadNotifier(ref),
    );
