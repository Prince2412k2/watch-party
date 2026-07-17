import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/mock_api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/still_card.dart';
import '../../ui/widgets/view_card.dart';
import 'login_screen.dart';

/// The home landing (Movies tab). Horizontal shelves in the redesigned web
/// order — Continue watching, Recently added, Downloading now, Next up,
/// Libraries — each on the shared shelf idiom (large light heading + scroll
/// arrows + a non-clipping horizontal rail), never a grid.
///
/// Continue watching / Next up use 16:9 [StillCard]s (with a watch-progress
/// bar); Recently added uses 2:3 [PosterCard]s with a mono NEW badge; Libraries
/// use 16:9 [ViewCard]s. Hovering a card drives the ambient wash off that
/// title (mirrors the web `setBalancedPoster`). The first title's `poster-<id>`
/// Hero tag flies into `/detail/:id`.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guest offline-browse (PLAN): a logged-out user's Movies tab IS the login
    // page — there's no server-backed home without a session.
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    if (!isAuthenticated) return const LoginScreen();

    final home = ref.watch(homeProvider);
    final latest = ref.watch(latestProvider);
    final api = ref.watch(apiClientProvider);
    final latestItems = latest.valueOrNull ?? const <LibraryItem>[];

    void setAmbient(String id) =>
        ref.read(ambientArtworkIdProvider.notifier).state = id;

    return home.when(
      loading: () => const _HomeSkeleton(),
      error: (e, _) => latestItems.isNotEmpty
          ? _CatalogFallback(items: latestItems, api: api, onAmbient: setAmbient)
          : ErrorState(
              title: 'Failed to load home',
              message: '$e',
              onRetry: () {
                ref.invalidate(homeProvider);
                ref.invalidate(latestProvider);
              },
            ),
      data: (data) {
        final downloads =
            ref.watch(enrichedDownloadsProvider).valueOrNull ??
            const <EnrichedDownload>[];

        if (data.views.isEmpty &&
            data.resume.isEmpty &&
            data.nextUp.isEmpty &&
            latestItems.isEmpty) {
          return const EmptyState(
            title: 'Your library is empty',
            message: 'Titles added to Jellyfin will show up here.',
            icon: Icons.movie_filter_outlined,
          );
        }

        String? imageUrl(LibraryItem item, ImageType type) =>
            api is MockApiClient ? null : api.imageUrl(item.id, type: type);

        final rails = <Widget>[
          if (data.resume.isNotEmpty)
            _Shelf(
              title: 'Continue watching',
              railHeight: _stillRailHeight,
              children: [
                for (final it in data.resume)
                  StillCard(
                    title: it.seriesName != null && it.name.isNotEmpty
                        ? it.name
                        : (it.seriesName ?? it.name),
                    subtitle: _stillSubtitle(it),
                    imageUrl: imageUrl(it, ImageType.thumb),
                    progress: _progress(it),
                    onHover: () => setAmbient(it.id),
                    onTap: () => context.go('/detail/${it.id}'),
                  ),
              ],
            ),
          if (latestItems.isNotEmpty)
            _Shelf(
              title: 'Recently added',
              railHeight: _posterRailHeight,
              children: [
                for (var i = 0; i < latestItems.length; i++)
                  _NewPoster(
                    item: latestItems[i],
                    imageUrl: imageUrl(latestItems[i], ImageType.primary),
                    heroTag: i == 0 ? 'poster-${latestItems[i].id}' : null,
                    onHover: () => setAmbient(latestItems[i].id),
                    onTap: () => context.go('/detail/${latestItems[i].id}'),
                  ),
              ],
            ),
          if (downloads.isNotEmpty)
            _Shelf(
              title: 'Downloading now',
              railHeight: _posterRailHeight,
              children: [
                for (final t in downloads)
                  PosterCard(
                    title: t.title,
                    subtitle: t.subtitle,
                    width: 170,
                    progress: t.progress.clamp(0, 1),
                    onTap: () => context.go('/downloads'),
                  ),
              ],
            ),
          if (data.nextUp.isNotEmpty)
            _Shelf(
              title: 'Next up',
              railHeight: _stillRailHeight,
              children: [
                for (final it in data.nextUp)
                  StillCard(
                    title: it.name,
                    subtitle: _stillSubtitle(it),
                    imageUrl: imageUrl(it, ImageType.thumb),
                    onHover: () => setAmbient(it.id),
                    onTap: () => context.go('/detail/${it.id}'),
                  ),
              ],
            ),
          if (data.views.isNotEmpty)
            _Shelf(
              title: 'Libraries',
              railHeight: _viewRailHeight,
              children: [
                for (final v in data.views)
                  ViewCard(
                    name: v.name,
                    imageUrl: imageUrl(v, ImageType.primary),
                    icon: _viewIcon(v),
                    onHover: () => setAmbient(v.id),
                    // A library view is a folder, not a playable title — open
                    // the browse shelves rather than the title-detail stage.
                    onTap: () => context.go('/series'),
                  ),
              ],
            ),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
          children: [
            for (var i = 0; i < rails.length; i++)
              Reveal(delay: AppMotion.stagger * i, child: rails[i]),
          ],
        );
      },
    );
  }
}

/// Recently-added 2:3 poster with a mono NEW badge over the artwork's
/// top-left. Wraps the frozen [PosterCard] rather than extending it.
class _NewPoster extends StatelessWidget {
  const _NewPoster({
    required this.item,
    required this.imageUrl,
    required this.onTap,
    required this.onHover,
    this.heroTag,
  });

  final LibraryItem item;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Stack(
        children: [
          PosterCard(
            title: item.name,
            subtitle: item.productionYear?.toString(),
            imageUrl: imageUrl,
            width: 170,
            heroTag: heroTag,
            onTap: onTap,
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'NEW',
                style: AppTheme.mono.copyWith(
                  color: wp.dim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _stillRailHeight = 300 * 9 / 16 + 62 + 50; // ~281
const double _posterRailHeight = 170 * 3 / 2 + 62 + 50; // ~367
const double _viewRailHeight = 300 * 9 / 16 + 60; // ~229 (no caption)

String? _stillSubtitle(LibraryItem it) {
  if (it.seriesName != null) {
    final ep = it.parentIndexNumber != null
        ? ' · S${it.parentIndexNumber}·E${it.indexNumber}'
        : '';
    return '${it.seriesName}$ep';
  }
  return it.productionYear?.toString();
}

double? _progress(LibraryItem it) => it.userData?.playedPercentage != null
    ? it.userData!.playedPercentage! / 100
    : null;

IconData _viewIcon(LibraryItem v) {
  final t = (v.collectionType ?? v.name).toLowerCase();
  if (t.contains('movie')) return Icons.movie_outlined;
  if (t.contains('tv') || t.contains('show') || t.contains('series')) {
    return Icons.tv_outlined;
  }
  if (t.contains('music')) return Icons.library_music_outlined;
  return Icons.folder_outlined;
}

/// The home shelf idiom — a Circular-Light heading with scroll arrows on its
/// right, over a horizontally-scrolling, non-clipping rail. Parameterised by
/// [railHeight] because home rails hold cards of different aspect ratios
/// (16:9 stills/views, 2:3 posters), unlike the uniform library [PosterShelf].
class _Shelf extends StatefulWidget {
  const _Shelf({
    required this.title,
    required this.children,
    required this.railHeight,
  });

  final String title;
  final List<Widget> children;
  final double railHeight;

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nudge(int direction) {
    if (!_controller.hasClients) return;
    final extent = _controller.position.viewportDimension * 0.8;
    final target = (_controller.offset + direction * extent).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final spaced = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 16));
      spaced.add(widget.children[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headlineLarge.copyWith(color: wp.text),
                  ),
                ),
                _ShelfArrow(icon: Icons.chevron_left, onTap: () => _nudge(-1)),
                const SizedBox(width: 7),
                _ShelfArrow(icon: Icons.chevron_right, onTap: () => _nudge(1)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: widget.railHeight,
            child: ListView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(right: 40, top: 20, bottom: 30),
              children: [
                for (final child in spaced)
                  Align(
                    alignment: Alignment.topLeft,
                    widthFactor: 1,
                    child: child,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfArrow extends StatefulWidget {
  const _ShelfArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ShelfArrow> createState() => _ShelfArrowState();
}

class _ShelfArrowState extends State<_ShelfArrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hover ? wp.surface : Colors.transparent,
          ),
          child: Icon(widget.icon, size: 22, color: _hover ? wp.text : wp.dim),
        ),
      ),
    );
  }
}

class _CatalogFallback extends ConsumerWidget {
  const _CatalogFallback({
    required this.items,
    required this.api,
    required this.onAmbient,
  });
  final List<LibraryItem> items;
  final ApiClient api;
  final ValueChanged<String> onAmbient;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
    children: [
      _Shelf(
        title: 'Recently added',
        railHeight: _posterRailHeight,
        children: [
          for (var i = 0; i < items.length; i++)
            _NewPoster(
              item: items[i],
              imageUrl: api is MockApiClient
                  ? null
                  : api.imageUrl(items[i].id),
              heroTag: i == 0 ? 'poster-${items[i].id}' : null,
              onHover: () => onAmbient(items[i].id),
              onTap: () => context.go('/detail/${items[i].id}'),
            ),
        ],
      ),
    ],
  );
}

/// Loading state: mimics the shelf layout — a couple of labeled rails of
/// poster-shaped skeletons.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  static const double _posterWidth = 190;
  static const double _posterHeight = _posterWidth * 5 / 3;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
    children: const [_RailSkeleton(), SizedBox(height: 40), _RailSkeleton()],
  );
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LoadingSkeleton(width: 220, height: 34),
      const SizedBox(height: AppSpacing.md),
      SizedBox(
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
