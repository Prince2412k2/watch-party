import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Real Browse screen (E3 T3.2): a search box, a type filter row, and a
/// responsive poster grid over [browseItemsProvider]. Replaces the Phase-0
/// placeholder.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  late final TextEditingController _searchCtrl =
      TextEditingController(text: ref.read(browseQueryProvider));

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
          Row(
            children: [
              for (final f in BrowseTypeFilter.values) ...[
                AppChip(
                  label: switch (f) {
                    BrowseTypeFilter.all => 'All',
                    BrowseTypeFilter.movie => 'Movies',
                    BrowseTypeFilter.series => 'Series',
                  },
                  selected: typeFilter == f,
                  onTap: () => ref.read(browseTypeFilterProvider.notifier).state = f,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        const tileWidth = 160.0;
        final columns = (constraints.maxWidth / (tileWidth + AppSpacing.lg))
            .floor()
            .clamp(2, 12);
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
            return PosterCard(
              title: item.name,
              subtitle: item.productionYear?.toString(),
              imageUrl: api.imageUrl(item.id),
              width: tileWidth,
              progress: item.userData?.playedPercentage != null
                  ? item.userData!.playedPercentage! / 100
                  : null,
              onTap: () => context.go('/detail/${item.id}'),
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
    return GridView.builder(
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        childAspectRatio: 0.52,
      ),
      itemBuilder: (context, i) => const LoadingSkeleton(height: 240, borderRadius: AppSpacing.radius),
    );
  }
}
