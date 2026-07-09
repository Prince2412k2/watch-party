import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../player/video_view.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Real title-detail screen (E3 T3.3): poster + metadata, a PLAY button that
/// opens the player, and a mount point for E8's real `DownloadButton`.
/// Replaces the Phase-0 placeholder.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(itemDetailProvider(itemId));
    final api = ref.watch(apiClientProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: detail.when(
          loading: () => const _DetailSkeleton(),
          error: (e, _) => ErrorState(
            title: 'Failed to load title',
            message: '$e',
            onRetry: () => ref.invalidate(itemDetailProvider(itemId)),
          ),
          data: (item) => _DetailBody(item: item, api: api),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item, required this.api});
  final LibraryItem item;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final runtimeMinutes = item.runTimeTicks != null
        ? (item.runTimeTicks! / 600000000).round()
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: SizedBox(
                width: 260,
                child: Image.network(
                  api.imageUrl(item.id),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.surface2,
                    child: Icon(Icons.movie_outlined, color: AppColors.faint, size: 40),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                  icon: const Icon(Icons.arrow_back, color: AppColors.dim),
                ),
                Text(item.name, style: AppTheme.displaySmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (item.productionYear != null) AppChip(label: '${item.productionYear}'),
                    if (runtimeMinutes != null) AppChip(label: '${runtimeMinutes}m'),
                    if (item.officialRating != null) AppChip(label: item.officialRating!),
                    if (item.communityRating != null)
                      AppChip(label: item.communityRating!.toStringAsFixed(1), icon: Icons.star_outline),
                    for (final genre in item.genres) AppChip(label: genre),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                if (item.overview != null)
                  Text(item.overview!, style: AppTheme.body.copyWith(height: 1.5)),
                const SizedBox(height: AppSpacing.xxl),
                Row(
                  children: [
                    AppButton(
                      label: 'Play',
                      icon: Icons.play_arrow,
                      variant: AppButtonVariant.primary,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PlayerView(itemId: item.id)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // Mount point for E8's real DownloadButton (resumable
                    // downloader + progress UI). Left as a disabled affordance
                    // so the layout is final; E8 swaps this widget in place.
                    const AppButton(
                      label: 'Download',
                      icon: Icons.download_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoadingSkeleton(width: 260, height: 390, borderRadius: AppSpacing.radiusLg),
            SizedBox(width: AppSpacing.xxl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LoadingSkeleton(width: 240, height: 32),
                  SizedBox(height: AppSpacing.lg),
                  LoadingSkeleton(width: 400, height: 16),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Local stand-in for E4.2's `lib/player/player_view.dart` `PlayerView`. That
/// widget does not exist yet in this worktree; once it lands, swap this
/// import/usage for the real one (same `itemId` constructor param expected).
/// It mints a signed native stream URL (frozen `ApiClient.nativeStreamUrl`)
/// and renders it through the real `MediaKitPlayerController` + `VideoView`
/// so Play is fully wired end-to-end even before the player chrome (E4.2)
/// exists.
class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({super.key, required this.itemId});
  final String itemId;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final api = ref.read(apiClientProvider);
      final stream = await api.nativeStreamUrl(widget.itemId, purpose: 'stream');
      final controller = ref.read(playerControllerProvider);
      await controller.open(stream.url, autoplay: true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(playerControllerProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: VideoView(controller: controller)),
          if (_error != null)
            Center(
              child: ErrorState(title: 'Playback failed', message: _error),
            ),
          Positioned(
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
