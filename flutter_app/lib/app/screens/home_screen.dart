import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/mock_api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import 'login_screen.dart';

/// The real Home screen (E3 T3.1): Continue Watching / Next Up / Libraries
/// rails over the real [homeProvider] (`GET /api/library/home`). Replaces the
/// Phase-0 mock layout.
///
/// Redesign (PKG-A): rails stagger their posters in as data loads
/// ([StaggeredList]), each rail lifts in with a short [Reveal] delay, the
/// loading state mimics real poster rails instead of a single box, and the
/// first poster of each title gets a `poster-<id>` Hero tag for a continuous
/// flight into `/detail/:id`. The [AsyncValue.when] +
/// [ErrorState]/[EmptyState] structure is unchanged.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guest offline-browse (PLAN): a logged-out user's "Home" tab IS the
    // login page — there's no server-backed home to show without a session,
    // and this keeps the guest shell at just two tabs (Home, Downloaded)
    // instead of a dedicated /login route swap.
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    if (!isAuthenticated) return const LoginScreen();

    final home = ref.watch(homeProvider);
    final latest = ref.watch(latestProvider);
    final api = ref.watch(apiClientProvider);
    final latestItems = latest.valueOrNull ?? const <LibraryItem>[];

    return home.when(
      loading: () => const _HomeSkeleton(),
      error: (e, _) => latestItems.isNotEmpty
          ? _CatalogFallback(items: latestItems, api: api)
          : ErrorState(
              title: 'Failed to load home',
              message: '$e',
              onRetry: () {
                ref.invalidate(homeProvider);
                ref.invalidate(latestProvider);
              },
            ),
      data: (data) {
        if (data.views.isEmpty && data.resume.isEmpty && data.nextUp.isEmpty && latestItems.isEmpty) {
          return const EmptyState(
            title: 'Your library is empty',
            message: 'Titles added to Jellyfin will show up here.',
            icon: Icons.movie_filter_outlined,
          );
        }

        // A title can appear in more than one rail (e.g. Continue Watching and
        // Libraries). A Hero tag must be unique per screen, so the FIRST time
        // an id is seen it claims `poster-<id>` and every later repeat gets a
        // null tag. Evaluated left-to-right, so the earlier rails win the tag.
        final claimed = <String>{};
        List<String?> heroTags(List<LibraryItem> items) => [
          for (final item in items)
            claimed.add(item.id) ? 'poster-${item.id}' : null,
        ];

        final rails = <Widget>[
          _Rail(
            title: 'Recently Added',
            items: latestItems,
            api: api,
            heroTags: heroTags(latestItems),
          ),
          _Rail(
            title: 'Continue Watching',
            items: data.resume,
            api: api,
            heroTags: heroTags(data.resume),
          ),
          _Rail(
            title: 'Next Up',
            items: data.nextUp,
            api: api,
            heroTags: heroTags(data.nextUp),
          ),
          _Rail(
            title: 'Libraries',
            items: data.views,
            api: api,
            heroTags: heroTags(data.views),
          ),
        ];

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          children: [
            const Text('Home', style: AppTheme.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            for (var i = 0; i < rails.length; i++)
              Reveal(delay: AppMotion.stagger * i, child: rails[i]),
          ],
        );
      },
    );
  }
}

class _CatalogFallback extends StatelessWidget {
  const _CatalogFallback({required this.items, required this.api});
  final List<LibraryItem> items;
  final ApiClient api;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          const Text('Home', style: AppTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          _Rail(
            title: 'Recently Added',
            items: items,
            api: api,
            heroTags: [for (final item in items) 'poster-${item.id}'],
          ),
        ],
      );
}

/// A horizontally-scrolling rail of posters. Posters cascade in via
/// [StaggeredList]; the rail height is derived from the [PosterCard] geometry
/// (image = width / aspect + caption) rather than a hard-coded constant.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.title,
    required this.items,
    required this.api,
    required this.heroTags,
  });

  final String title;
  final List<LibraryItem> items;
  final ApiClient api;

  /// Hero tag per item (null where a duplicate id already claimed the tag).
  final List<String?> heroTags;

  static const double _posterWidth = 160;
  static const double _posterAspect = 2 / 3;

  /// Room under the poster for the two-line caption + its gap (with a little
  /// headroom for larger text scales).
  static const double _captionAllowance = 56;

  /// Poster image block height (what the [PosterCard] renders above the text).
  static const double _posterHeight = _posterWidth / _posterAspect;
  static const double _railHeight = _posterHeight + _captionAllowance;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: _railHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: StaggeredList(
              direction: Axis.horizontal,
              spacing: AppSpacing.lg,
              children: [
                for (var i = 0; i < items.length; i++)
                  PosterCard(
                    title: items[i].name,
                    subtitle: items[i].productionYear?.toString(),
                    imageUrl: api is MockApiClient
                        ? null
                        : api.imageUrl(items[i].id),
                    width: _posterWidth,
                    aspectRatio: _posterAspect,
                    heroTag: heroTags[i],
                    progress: items[i].userData?.playedPercentage != null
                        ? items[i].userData!.playedPercentage! / 100
                        : null,
                    onTap: () => context.go('/detail/${items[i].id}'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

/// Loading state: mimics the real layout — a page-title block over a couple of
/// labeled rails, each a row of poster-shaped skeletons — instead of a single
/// box, so the shape of the incoming content is legible while it loads.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  static const double _posterWidth = 160;
  static const double _posterHeight = _posterWidth / (2 / 3);

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    children: const [
      LoadingSkeleton(width: 120, height: 28),
      SizedBox(height: AppSpacing.xl),
      _RailSkeleton(),
      SizedBox(height: AppSpacing.xxl),
      _RailSkeleton(),
    ],
  );
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LoadingSkeleton(width: 160, height: 18),
      const SizedBox(height: AppSpacing.md),
      SizedBox(
        // A horizontal ListView clips its overflow, so this never trips a
        // RenderFlex overflow at narrow widths (unlike a plain Row).
        height: _HomeSkeleton._posterHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 8,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
          itemBuilder: (_, _) => const LoadingSkeleton(
            width: _HomeSkeleton._posterWidth,
            height: _HomeSkeleton._posterHeight,
            borderRadius: AppSpacing.radius,
          ),
        ),
      ),
    ],
  );
}
