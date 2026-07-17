import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'providers.dart';

/// Home/browse data (PLAN §3.8 / E3). Async providers over [apiClientProvider].
/// The shapes below are the frozen Phase-0 contract; E3 adds the browse
/// filter state (query + type) that drives [browseItemsProvider].

/// The aggregated home payload (views + resume + next-up).
final homeProvider = StreamProvider<HomeData>((ref) {
  return ref.watch(catalogRepositoryProvider).home(_catalogNamespace(ref));
});

/// The same catalog rail the web home shows. Unlike Continue Watching / Next
/// Up, it is populated for a brand-new account with no playback history.
final latestProvider = StreamProvider<List<LibraryItem>>((ref) {
  return ref.watch(catalogRepositoryProvider).latest(_catalogNamespace(ref));
});

/// The flat library list, optionally scoped to a parent (library view) id.
final libraryProvider =
    StreamProvider.family<List<LibraryItem>, String?>((ref, parentId) {
  return ref
      .watch(catalogRepositoryProvider)
      .items(_catalogNamespace(ref), parentId: parentId);
});

/// A single title's full detail.
final itemDetailProvider =
    StreamProvider.family<LibraryItem, String>((ref, id) {
  return ref.watch(catalogRepositoryProvider).item(_catalogNamespace(ref), id);
});

/// Search results for a query.
final searchProvider =
    FutureProvider.family<List<LibraryItem>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  final items = await ref.watch(libraryProvider(null).future);
  final normalized = query.toLowerCase();
  return items
      .where((item) => item.name.toLowerCase().contains(normalized))
      .toList();
});

/// A parent item's direct children — a Series' Seasons, or a Season's
/// Episodes. Used by the detail screen to browse a Series instead of playing
/// it directly.
final itemChildrenProvider =
    StreamProvider.family<List<LibraryItem>, String>((ref, parentId) {
  return ref
      .watch(catalogRepositoryProvider)
      .children(_catalogNamespace(ref), parentId);
});

/// A season paired with its episodes — one row of the show-detail season
/// selector + episode dock.
typedef SeasonEpisodes = ({LibraryItem season, List<LibraryItem> episodes});

/// A series' seasons, each with its episodes fetched — the show-detail stage
/// reads this to build the right-hand season selector and the bottom episode
/// dock (mirrors the web `Details` season-rows fetch: children of the series,
/// then children of each season).
final seriesSeasonsProvider =
    FutureProvider.family<List<SeasonEpisodes>, String>((ref, seriesId) async {
  final api = ref.read(apiClientProvider);
  final seasons = await api.children(seriesId);
  return Future.wait(seasons.map((season) async {
    final episodes = await api.children(season.id);
    return (season: season, episodes: episodes);
  }));
});

/// The audio/subtitle tracks available for a movie/episode — the detail stage's
/// track menu reads this (`POST /api/library/playback-info/:id`). Invalidate it
/// after a subtitle upload/delete to re-list the tracks.
final detailPlaybackProvider =
    FutureProvider.family<PlaybackInfo, String>((ref, id) async {
  return ref.read(apiClientProvider).playbackInfo(id);
});

/// One actively-downloading torrent, as surfaced on the home "Downloading now"
/// rail. A trimmed projection of the enriched torrent payload — just what the
/// rail card renders.
class EnrichedDownload {
  const EnrichedDownload({
    required this.hash,
    this.displayTitle,
    this.name,
    this.subtitle,
    this.progress = 0,
    this.dlspeed = 0,
    this.state,
  });

  final String hash;
  final String? displayTitle;
  final String? name;
  final String? subtitle;
  final double progress;
  final num dlspeed;
  final String? state;

  String get title => displayTitle ?? name ?? 'Downloading';
}

const Set<String> _activeDownloadStates = {
  'downloading',
  'forcedDL',
  'metaDL',
  'checkingDL',
  'allocating',
  'stalledDL',
  'queuedDL',
};

/// Actively-downloading torrents from `GET /api/servarr/downloads/enriched`
/// (the superset endpoint carrying a clean title/subtitle per item). Degrades
/// to an empty list when Servarr is unconfigured or unreachable, so the
/// "Downloading now" rail simply doesn't render.
final enrichedDownloadsProvider =
    FutureProvider<List<EnrichedDownload>>((ref) async {
  try {
    final data = await ref.read(apiClientProvider).servarrGet(
          'downloads/enriched',
        );
    if (data is! List) return const [];
    final items = data.whereType<Map>().map((m) {
      return EnrichedDownload(
        hash: '${m['hash']}',
        displayTitle: m['displayTitle'] as String?,
        name: m['name'] as String?,
        subtitle: m['subtitle'] as String?,
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        dlspeed: (m['dlspeed'] as num?) ?? 0,
        state: m['state'] as String?,
      );
    });
    return items
        .where((t) => _activeDownloadStates.contains(t.state) && t.dlspeed > 0)
        .toList();
  } catch (_) {
    return const [];
  }
});

/// Basic type filter for the Browse grid. `all` means no filtering.
enum BrowseTypeFilter { all, movie, series }

extension on BrowseTypeFilter {
  String? get jellyfinType => switch (this) {
        BrowseTypeFilter.all => null,
        BrowseTypeFilter.movie => 'Movie',
        BrowseTypeFilter.series => 'Series',
      };
}

/// The Browse screen's live search text (empty = browse the whole library).
final browseQueryProvider = StateProvider<String>((ref) => '');

/// The Browse screen's type filter (All / Movie / Series).
final browseTypeFilterProvider =
    StateProvider<BrowseTypeFilter>((ref) => BrowseTypeFilter.all);

/// Combines [browseQueryProvider] + [browseTypeFilterProvider] into the list
/// the Browse grid renders: searches when there's a query, otherwise lists
/// the full library — either way filtered client-side by type (the server
/// doesn't expose a type filter on `/api/library/items` or `/search`).
final browseItemsProvider = FutureProvider<List<LibraryItem>>((ref) async {
  final query = ref.watch(browseQueryProvider).trim();
  final type = ref.watch(browseTypeFilterProvider).jellyfinType;
  final api = ref.read(apiClientProvider);

  final items = query.isEmpty ? await api.items() : await api.search(query);
  if (type == null) return items;
  return items.where((i) => i.type == type).toList();
});

/// A route-owned catalog slice. Unlike [browseItemsProvider], this has no
/// mutable global filter, so Movies and Shows cannot leak state into each other.
final browseByTypeProvider =
    StreamProvider.family<List<LibraryItem>, BrowseTypeFilter>((ref, filter) {
  final type = filter.jellyfinType;
  return ref
      .watch(catalogRepositoryProvider)
      .items(_catalogNamespace(ref))
      .map((items) => type == null
          ? items
          : items.where((item) => item.type == type).toList());
});

String? _catalogNamespace(Ref ref) {
  final userId = ref.watch(authProvider).user?.userId;
  if (userId == null) return null;
  return '${ref.watch(apiClientProvider).baseUrl}|$userId';
}
