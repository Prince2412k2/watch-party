import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/mock_api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// The real Home screen (E3 T3.1): Continue Watching / Next Up / Libraries
/// rails over the real [homeProvider] (`GET /api/library/home`). Replaces the
/// Phase-0 mock layout.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final api = ref.watch(apiClientProvider);

    return home.when(
      loading: () => const _HomeSkeleton(),
      error: (e, _) => ErrorState(
        title: 'Failed to load home',
        message: '$e',
        onRetry: () => ref.invalidate(homeProvider),
      ),
      data: (data) {
        if (data.views.isEmpty && data.resume.isEmpty && data.nextUp.isEmpty) {
          return const EmptyState(
            title: 'Your library is empty',
            message: 'Titles added to Jellyfin will show up here.',
            icon: Icons.movie_filter_outlined,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          children: [
            const Text('Home', style: AppTheme.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            _Rail(title: 'Continue Watching', items: data.resume, api: api),
            _Rail(title: 'Next Up', items: data.nextUp, api: api),
            _Rail(title: 'Libraries', items: data.views, api: api),
          ],
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.items, required this.api});
  final String title;
  final List<LibraryItem> items;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              final item = items[i];
              return PosterCard(
                title: item.name,
                subtitle: item.productionYear?.toString(),
                imageUrl: api is MockApiClient ? null : api.imageUrl(item.id),
                progress: item.userData?.playedPercentage != null
                    ? item.userData!.playedPercentage! / 100
                    : null,
                onTap: () => context.go('/detail/${item.id}'),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoadingSkeleton(width: 120, height: 28),
            SizedBox(height: AppSpacing.xl),
            LoadingSkeleton(width: 200, height: 240, borderRadius: AppSpacing.radius),
          ],
        ),
      );
}
