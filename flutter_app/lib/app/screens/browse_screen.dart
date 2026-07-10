import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Real Browse screen (E3 T3.2): a search box, a type filter, and a responsive
/// poster grid over [browseItemsProvider]. Replaces the Phase-0 placeholder.
///
/// Redesign (PKG-A): the type filter is a shadcn toggle-group segmented control
/// (same [browseTypeFilterProvider] + behavior as the old chip row); the
/// loading grid mirrors the real responsive column count; posters stagger in
/// via [Reveal] and carry a `poster-<id>` Hero tag into `/detail/:id`.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

/// Fixed poster tile width the responsive column count is derived from.
const double _tileWidth = 160;

/// Columns for the poster grid at [maxWidth]. Shared by the real grid and its
/// skeleton so the placeholder matches the eventual layout exactly.
int _gridColumns(double maxWidth) =>
    (maxWidth / (_tileWidth + AppSpacing.lg)).floor().clamp(2, 12);

String _filterLabel(BrowseTypeFilter f) => switch (f) {
  BrowseTypeFilter.all => 'All',
  BrowseTypeFilter.movie => 'Movies',
  BrowseTypeFilter.series => 'Series',
};

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  late final TextEditingController _searchCtrl = TextEditingController(
    text: ref.read(browseQueryProvider),
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(browseItemsProvider);
    final typeFilter = ref.watch(browseTypeFilterProvider);
    final api = ref.watch(apiClientProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Browse', style: AppTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          AppTextField(
            controller: _searchCtrl,
            hint: 'Search your library…',
            onChanged: (v) => ref.read(browseQueryProvider.notifier).state = v,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Segmented control (shadcn toggle-group). Selecting a segment writes
          // the same value the old chip row did, so the filter behavior and the
          // [browseTypeFilterProvider] contract are unchanged.
          sc.ButtonGroup(
            children: [
              for (final f in BrowseTypeFilter.values)
                sc.Toggle(
                  value: typeFilter == f,
                  onChanged: (_) =>
                      ref.read(browseTypeFilterProvider.notifier).state = f,
                  child: Text(_filterLabel(f)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: items.when(
              loading: () => const _BrowseGridSkeleton(),
              error: (e, _) => ErrorState(
                title: 'Failed to load library',
                message: '$e',
                onRetry: () => ref.invalidate(browseItemsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    title: 'No titles found',
                    message: 'Try a different search or filter.',
                    icon: Icons.search_off_outlined,
                  );
                }
                return _BrowseGrid(items: list, api: api);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({required this.items, required this.api});
  final List<LibraryItem> items;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    // Unique Hero tag per screen: the first time an id appears it claims
    // `poster-<id>`; any repeat gets a null tag (Flutter throws on duplicate
    // Hero tags in one screen). Precomputed by list order so it's independent
    // of the lazy grid's build order.
    final claimed = <String>{};
    final heroTags = [
      for (final item in items)
        claimed.add(item.id) ? 'poster-${item.id}' : null,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumns(constraints.maxWidth);
        return GridView.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            childAspectRatio: 0.52,
          ),
          itemBuilder: (context, i) {
            final item = items[i];
            return Reveal(
              // Cap the per-index delay so the first screenful cascades but
              // later items (built lazily on scroll) don't lag behind.
              delay: AppMotion.stagger * (i < 10 ? i : 10),
              child: PosterCard(
                title: item.name,
                subtitle: item.productionYear?.toString(),
                imageUrl: api.imageUrl(item.id),
                width: _tileWidth,
                heroTag: heroTags[i],
                progress: item.userData?.playedPercentage != null
                    ? item.userData!.playedPercentage! / 100
                    : null,
                onTap: () => context.go('/detail/${item.id}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _BrowseGridSkeleton extends StatelessWidget {
  const _BrowseGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumns(constraints.maxWidth);
        return GridView.builder(
          // A few full rows of placeholders so the grid's shape reads while it
          // loads, at the same column count the real grid will use.
          itemCount: columns * 3,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            childAspectRatio: 0.52,
          ),
          itemBuilder: (context, i) =>
              const LoadingSkeleton(borderRadius: AppSpacing.radius),
        );
      },
    );
  }
}
