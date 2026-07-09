import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/mock_api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// The mock home screen (PLAN Phase 0 boot target). Renders sections from the
/// (mock) [homeProvider] so the app visibly boots through the router. E3
/// replaces the layout with the real hero + rails.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final api = ref.watch(apiClientProvider);

    return home.when(
      loading: () => const _HomeSkeleton(),
      error: (e, _) => Center(
        child: Text('Failed to load home\n$e',
            textAlign: TextAlign.center, style: AppTheme.dim),
      ),
      data: (data) => ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          const Text('Home', style: AppTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          _Rail(title: 'Continue Watching', items: data.resume, api: api),
          _Rail(title: 'Next Up', items: data.nextUp, api: api),
          _Rail(title: 'Libraries', items: data.views, api: api),
        ],
      ),
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
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        ),
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
