import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Library browse (Shows tab). Horizontal [PosterShelf]s — never a grid: a main
/// shelf over the current filter, then extra shelves for genres that form a
/// meaningful subset (more than one title, fewer than the whole set). No search
/// field (design guide §Library and discovery shelves); the type filter keeps
/// the Movies/Shows separation.
///
/// The first poster of each shelf is emphasized and carries the `poster-<id>`
/// Hero tag into `/detail/:id`; hovering a poster drives the ambient wash.
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  static const double _posterWidth = 190;

  String _filterLabel(BrowseTypeFilter f) => switch (f) {
    BrowseTypeFilter.all => 'Library',
    BrowseTypeFilter.movie => 'Movies',
    BrowseTypeFilter.series => 'Shows',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(browseItemsProvider);
    final typeFilter = ref.watch(browseTypeFilterProvider);
    final api = ref.watch(apiClientProvider);

    void setAmbient(String id) =>
        ref.read(ambientArtworkIdProvider.notifier).state = id;

    Widget posterFor(LibraryItem item, {required bool first, String? heroTag}) {
      return MouseRegion(
        onEnter: (_) => setAmbient(item.id),
        child: PosterCard(
          title: item.name,
          rating: item.communityRating,
          imageUrl: api.imageUrl(item.id),
          width: _posterWidth,
          aspectRatio: 3 / 5,
          emphasized: first,
          heroTag: heroTag,
          onTap: () => context.go('/detail/${item.id}'),
        ),
      );
    }

    return items.when(
      loading: () => const _BrowseSkeleton(),
      error: (e, _) => ErrorState(
        title: 'Failed to load library',
        message: '$e',
        onRetry: () => ref.invalidate(browseItemsProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            title: 'No titles here yet',
            message: 'Add something from Discover.',
            icon: Icons.movie_filter_outlined,
          );
        }

        // Unique Hero tag per screen: first occurrence of an id claims
        // `poster-<id>`; repeats get null (Flutter throws on duplicate tags).
        final claimed = <String>{};
        String? heroTag(String id) =>
            claimed.add(id) ? 'poster-$id' : null;

        // Genre-subset shelves: a genre that more than one — but not all —
        // titles share (web GridView.genreRows).
        final genres = <String>{for (final it in list) ...it.genres};
        final genreShelves = <MapEntry<String, List<LibraryItem>>>[];
        for (final g in genres) {
          final subset = list.where((it) => it.genres.contains(g)).toList();
          if (subset.length > 1 && subset.length < list.length) {
            genreShelves.add(MapEntry(g, subset));
          }
        }

        final shelves = <Widget>[
          PosterShelf(
            title: _filterLabel(typeFilter),
            leftInset: 0,
            children: [
              for (var i = 0; i < list.length; i++)
                posterFor(list[i], first: i == 0, heroTag: heroTag(list[i].id)),
            ],
          ),
          for (final entry in genreShelves)
            PosterShelf(
              title: entry.key,
              leftInset: 0,
              children: [
                for (var i = 0; i < entry.value.length; i++)
                  posterFor(entry.value[i], first: i == 0),
              ],
            ),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 24, bottom: 8),
              child: sc.ButtonGroup(
                children: [
                  for (final f in BrowseTypeFilter.values)
                    sc.Toggle(
                      value: typeFilter == f,
                      onChanged: (_) => ref
                          .read(browseTypeFilterProvider.notifier)
                          .state = f,
                      child: Text(_filterLabel(f)),
                    ),
                ],
              ),
            ),
            for (var i = 0; i < shelves.length; i++)
              Reveal(delay: AppMotion.stagger * i, child: shelves[i]),
          ],
        );
      },
    );
  }
}

class _BrowseSkeleton extends StatelessWidget {
  const _BrowseSkeleton();

  static const double _w = 190;
  static const double _h = _w * 5 / 3;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
    children: [
      const LoadingSkeleton(width: 220, height: 34),
      const SizedBox(height: AppSpacing.md),
      SizedBox(
        height: _h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 8,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
          itemBuilder: (_, _) => const LoadingSkeleton(
            width: _w,
            height: _h,
            borderRadius: AppSpacing.radius,
          ),
        ),
      ),
    ],
  );
}
