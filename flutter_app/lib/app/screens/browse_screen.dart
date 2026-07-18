import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Route-scoped Movies or Shows library. Horizontal [PosterShelf]s — never a
/// grid: a main shelf over the current type, then extra shelves for genres that form a
/// meaningful subset (more than one title, fewer than the whole set). No search
/// field (design guide §Library and discovery shelves).
///
/// Shelf selection carries the `poster-<id>` Hero tag into `/detail/:id` and
/// drives the ambient wash from mouse, wheel, or keyboard movement.
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key, required this.type});

  final BrowseTypeFilter type;

  static const double _posterWidth = 190;

  String get _title => type == BrowseTypeFilter.movie ? 'Movies' : 'Shows';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(browseByTypeProvider(type));
    final api = ref.watch(apiClientProvider);

    void setAmbient(String id) =>
        ref.read(ambientArtworkIdProvider.notifier).state = id;

    Widget posterFor(LibraryItem item, {String? heroTag}) {
      return MouseRegion(
        onEnter: (_) => setAmbient(item.id),
        child: PosterCard(
          title: item.name,
          rating: item.communityRating,
          imageUrl: api.imageUrl(item.id, tag: item.imageTags?['Primary']),
          width: _posterWidth,
          aspectRatio: 3 / 5,
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
        onRetry: () => ref.invalidate(browseByTypeProvider(type)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            title: 'No titles here yet',
            message: 'Add something from Discover.',
            icon: Icons.movie_filter_outlined,
          );
        }

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
            title: _title,
            leftInset: 0,
            itemCount: list.length,
            autofocus: true,
            onSelectionChanged: (index) => setAmbient(list[index].id),
            onActivate: (index) => context.go('/detail/${list[index].id}'),
            itemBuilder: (_, index) =>
                posterFor(list[index], heroTag: 'poster-${list[index].id}'),
          ),
          for (final entry in genreShelves)
            PosterShelf(
              title: entry.key,
              leftInset: 0,
              itemCount: entry.value.length,
              onSelectionChanged: (index) =>
                  setAmbient(entry.value[index].id),
              onActivate: (index) =>
                  context.go('/detail/${entry.value[index].id}'),
              itemBuilder: (_, index) => posterFor(entry.value[index]),
            ),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
          children: [
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
