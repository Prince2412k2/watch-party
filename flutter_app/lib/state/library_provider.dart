import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'providers.dart';

/// Home/browse data (PLAN §3.8 / E3). Async providers over [apiClientProvider].
/// The shapes below are the frozen Phase-0 contract; E3 adds the browse
/// filter state (query + type) that drives [browseItemsProvider].

/// The aggregated home payload (views + resume + next-up).
final homeProvider = FutureProvider<HomeData>((ref) async {
  return ref.read(apiClientProvider).home();
});

/// The same catalog rail the web home shows. Unlike Continue Watching / Next
/// Up, it is populated for a brand-new account with no playback history.
final latestProvider = FutureProvider<List<LibraryItem>>((ref) async {
  return ref.read(apiClientProvider).latest();
});

/// The flat library list, optionally scoped to a parent (library view) id.
final libraryProvider =
    FutureProvider.family<List<LibraryItem>, String?>((ref, parentId) async {
  return ref.read(apiClientProvider).items(parentId: parentId);
});

/// A single title's full detail.
final itemDetailProvider =
    FutureProvider.family<LibraryItem, String>((ref, id) async {
  return ref.read(apiClientProvider).item(id);
});

/// Search results for a query.
final searchProvider =
    FutureProvider.family<List<LibraryItem>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  return ref.read(apiClientProvider).search(query);
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
