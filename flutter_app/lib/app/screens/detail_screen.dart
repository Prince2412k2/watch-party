import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../player/offline_playback.dart';
import '../../player/player_view.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import 'subtitle_manager_dialog.dart';

/// Real title-detail screen. Full-bleed backdrop hero (matches the web
/// client's `Library.tsx` Detail view) with title/logo, rating/genre line,
/// runtime/resolution/HDR/size info line, a Play (or, for a Series, "Browse
/// episodes") button, plus Cast and external-link sections below. Series show
/// a Seasons rail instead of Play; a Season shows its Episodes as a list.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(itemDetailProvider(itemId));
    final api = ref.watch(apiClientProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: detail.when(
        loading: () => const SafeArea(child: _DetailSkeleton()),
        error: (e, _) => SafeArea(
          child: ErrorState(
            title: 'Failed to load title',
            message: '$e',
            onRetry: () => ref.invalidate(itemDetailProvider(itemId)),
          ),
        ),
        data: (item) => _DetailBody(item: item, api: api),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.item, required this.api});
  final LibraryItem item;
  final ApiClient api;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSeries = item.type == 'Series';
    final isSeason = item.type == 'Season';
    final cast = item.people.where((p) => p.type == 'Actor').take(16).toList();
    final imdb = item.providerIds['Imdb'];
    final tmdb = item.providerIds['Tmdb'];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(item: item, api: api, isSeries: isSeries),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSeries || isSeason)
                  _ChildrenSection(parent: item, isSeason: isSeason),
                if (cast.isNotEmpty) _CastSection(cast: cast, api: api),
                if (imdb != null || tmdb != null)
                  _LinksSection(imdb: imdb, tmdb: tmdb, isSeries: isSeries),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed backdrop with legibility gradient, title/logo, rating/genre
/// line, info line, overview, and the primary action.
class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.api, required this.isSeries});
  final LibraryItem item;
  final ApiClient api;
  final bool isSeries;

  @override
  Widget build(BuildContext context) {
    final ms = item.mediaSources.isNotEmpty ? item.mediaSources.first : null;
    final video = ms?.mediaStreams.firstWhere(
      (s) => s.type == 'Video',
      orElse: () => const MediaStream(),
    );
    final hasVideo = video?.type == 'Video';
    final resLabel = hasVideo ? _resolutionLabel(video!.height) : null;
    final hdr =
        hasVideo && video!.videoRange != null && video.videoRange != 'SDR'
        ? video.videoRange
        : null;
    final sizeLabel = ms?.size != null
        ? '${(ms!.size! / 1000000).round()}M'
        : null;
    final premiere = item.premiereDate != null
        ? _formatDate(item.premiereDate!)
        : null;
    final runtime = item.runTimeTicks != null
        ? '${(item.runTimeTicks! / 600000000).round()}m'
        : null;
    final infoLine = [
      runtime,
      premiere,
      resLabel,
      hdr,
      sizeLabel,
    ].whereType<String>().toList();

    final resumeTicks = item.userData?.playbackPositionTicks ?? 0;
    final resumeLabel = resumeTicks > 0
        ? '${(resumeTicks / 600000000).round()}m'
        : null;

    return Stack(
      children: [
        SizedBox(
          height: 520,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AuthedNetworkImage(
                api.imageUrl(
                  item.seriesId ?? item.id,
                  type: ImageType.backdrop,
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.surface2),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.bg,
                      AppColors.bg.withValues(alpha: 0.82),
                      AppColors.bg.withValues(alpha: 0.15),
                    ],
                    stops: const [0.0, 0.14, 0.62],
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.md,
                AppSpacing.xxl,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sc.IconButton.ghost(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                    icon: const Icon(Icons.arrow_back, color: AppColors.dim),
                  ),
                  const Spacer(),
                  _TitleOrLogo(item: item, api: api),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (item.communityRating != null)
                        AppChip(
                          label: item.communityRating!.toStringAsFixed(1),
                          icon: Icons.star_outline,
                        ),
                      if (item.criticRating != null)
                        AppChip(label: '${item.criticRating!.round()}%'),
                      if (item.officialRating != null)
                        AppChip(label: item.officialRating!),
                      for (final genre in item.genres.take(2))
                        AppChip(label: genre),
                    ],
                  ),
                  if (infoLine.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      infoLine.join('   ·   '),
                      style: AppTheme.mono.copyWith(color: AppColors.dim),
                    ),
                  ],
                  if (item.overview != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Text(
                        item.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      AppButton(
                        label: isSeries
                            ? 'Browse episodes'
                            : resumeLabel != null
                            ? 'Resume · $resumeLabel'
                            : 'Play',
                        icon: Icons.play_arrow,
                        variant: AppButtonVariant.primary,
                        onPressed: isSeries
                            ? null
                            : () => Navigator.of(
                                context,
                              ).push(_playerRoute(item)),
                      ),
                      if (!isSeries) ...[
                        const SizedBox(width: AppSpacing.md),
                        DownloadButton(
                          itemId: item.id,
                          title: item.name,
                          runTimeTicks: item.runTimeTicks,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        sc.IconButton.outline(
                          icon: const Icon(Icons.subtitles_outlined),
                          onPressed: () =>
                              showSubtitleManagerDialog(context, item.id),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The title, replaced by the title-treatment `Logo` art Jellyfin exposes for
/// most movies/shows, when one exists (falls back to plain text otherwise —
/// mirrors web's `DetailLogo`).
class _TitleOrLogo extends StatelessWidget {
  const _TitleOrLogo({required this.item, required this.api});
  final LibraryItem item;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 110),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: AuthedNetworkImage(
          api.imageUrl(item.seriesId ?? item.id, type: ImageType.logo),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Text(item.name, style: AppTheme.displaySmall),
        ),
      ),
    );
  }
}

String _resolutionLabel(int? height) {
  final h = height ?? 0;
  if (h >= 2160) return '4K';
  if (h >= 1080) return '1080P';
  if (h >= 720) return '720P';
  return h > 0 ? '${h}P' : '?P';
}

String _formatDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Seasons (for a Series) or Episodes (for a Season) below the hero.
class _ChildrenSection extends ConsumerWidget {
  const _ChildrenSection({required this.parent, required this.isSeason});
  final LibraryItem parent;
  final bool isSeason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(itemChildrenProvider(parent.id));
    return children.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: LoadingSkeleton(width: 160, height: 240),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: isSeason ? 'Episodes' : 'Seasons'),
              const SizedBox(height: AppSpacing.md),
              if (isSeason)
                Column(
                  children: [for (final ep in items) _EpisodeRow(episode: ep)],
                )
              else
                SizedBox(
                  height: 250,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, i) {
                      final season = items[i];
                      final api = ref.watch(apiClientProvider);
                      return PosterCard(
                        title: season.name,
                        imageUrl: api.imageUrl(season.id),
                        width: 160,
                        onTap: () => context.push('/detail/${season.id}'),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({required this.episode});
  final LibraryItem episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final runtime = episode.runTimeTicks != null
        ? '${(episode.runTimeTicks! / 600000000).round()}m'
        : null;
    return sc.Card(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: InkWell(
        onTap: () => Navigator.of(context).push(_playerRoute(episode)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: SizedBox(
                width: 128,
                height: 72,
                child: AuthedNetworkImage(
                  api.imageUrl(episode.id, type: ImageType.primary),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppColors.surface2),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    episode.indexNumber != null
                        ? '${episode.indexNumber}. ${episode.name}'
                        : episode.name,
                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (episode.overview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        episode.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(color: AppColors.dim),
                      ),
                    ),
                ],
              ),
            ),
            if (runtime != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Text(
                  runtime,
                  style: AppTheme.caption.copyWith(color: AppColors.faint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CastSection extends StatelessWidget {
  const _CastSection({required this.cast, required this.api});
  final List<Person> cast;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Cast'),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, i) {
                final p = cast[i];
                return SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: AuthedNetworkImage(
                            api.imageUrl(p.id, type: ImageType.primary),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: AppColors.surface2,
                              child: Icon(
                                Icons.person_outline,
                                color: AppColors.faint,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (p.role != null)
                        Text(
                          p.role!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(
                            color: AppColors.dim,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LinksSection extends StatelessWidget {
  const _LinksSection({
    required this.imdb,
    required this.tmdb,
    required this.isSeries,
  });
  final String? imdb;
  final String? tmdb;
  final bool isSeries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Link'),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (imdb != null)
                _LinkPill(
                  label: 'IMDb ↗',
                  uri: Uri.parse('https://www.imdb.com/title/$imdb/'),
                ),
              if (tmdb != null)
                _LinkPill(
                  label: 'TMDb ↗',
                  uri: Uri.parse(
                    'https://www.themoviedb.org/${isSeries ? 'tv' : 'movie'}/$tmdb',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkPill extends StatelessWidget {
  const _LinkPill({required this.label, required this.uri});
  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return sc.Button.outline(
      onPressed: () => launchUrl(uri),
      child: Text(label, style: AppTheme.mono),
    );
  }
}

/// Fade transition into the solo player (per the redesign's motion system),
/// replacing the hard-cut `MaterialPageRoute`.
Route<void> _playerRoute(LibraryItem item) {
  return PageRouteBuilder<void>(
    transitionDuration: AppMotion.page,
    reverseTransitionDuration: AppMotion.page,
    pageBuilder: (context, animation, secondaryAnimation) =>
        _SoloPlayer(itemId: item.id, title: item.name),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppMotion.emphasized,
          ),
          child: child,
        ),
  );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoadingSkeleton(width: double.infinity, height: 320),
        SizedBox(height: AppSpacing.lg),
        LoadingSkeleton(width: 240, height: 32),
        SizedBox(height: AppSpacing.lg),
        LoadingSkeleton(width: 400, height: 16),
      ],
    ),
  );
}

/// Solo playback launcher for the detail screen. Opens the shared
/// [playerControllerProvider] preferring a locally-downloaded copy over the
/// network stream (E8.3 `openPreferringOffline`), then mounts the real E4.2
/// [PlayerView] chrome. The controller is owned by the provider, so this hands
/// it to `PlayerView(controller:)` (which never disposes a controller it
/// didn't create).
class _SoloPlayer extends ConsumerStatefulWidget {
  const _SoloPlayer({required this.itemId, required this.title});
  final String itemId;
  final String title;

  @override
  ConsumerState<_SoloPlayer> createState() => _SoloPlayerState();
}

class _SoloPlayerState extends ConsumerState<_SoloPlayer> {
  Object? _error;
  bool _ready = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    // Leaving the solo player (back-navigation): stop playback. The controller
    // is provider-owned and shared with the party screen, so we don't dispose
    // it here — but nothing else pauses it when this route pops, which would
    // otherwise leave audio playing in a screen the user already left.
    unawaited(ref.read(playerControllerProvider).pause());
    if (_isFullscreen) unawaited(windowManager.setFullScreen(false));
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullscreen = next);
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      final api = ref.read(apiClientProvider);
      final stream = await api.nativeStreamUrl(
        widget.itemId,
        purpose: 'stream',
      );
      final controller = ref.read(playerControllerProvider);
      await openPreferringOffline(
        ref,
        controller,
        itemId: widget.itemId,
        streamUrl: stream.url,
        autoplay: true,
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? Center(
              child: ErrorState(
                title: 'Playback failed',
                message: _error is ApiException
                    ? (_error as ApiException).message
                    : 'Could not open this title. Check your connection and try again.',
                onRetry: _open,
              ),
            )
          : !_ready
          ? const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.text,
                ),
              ),
            )
          : Stack(
              children: [
                PlayerView(
                  controller: ref.watch(playerControllerProvider),
                  itemId: widget.itemId,
                  apiClient: ref.watch(apiClientProvider),
                  title: widget.title,
                  onBack: () => Navigator.of(context).maybePop(),
                  onToggleFullscreen: _toggleFullscreen,
                  isFullscreen: _isFullscreen,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(
                    child: _StartPartyButton(itemId: widget.itemId),
                  ),
                ),
              ],
            ),
    );
  }
}

/// "Start a party" affordance floated over solo playback (E3 title detail),
/// so a party can be spun up MID-MOVIE instead of only from the party
/// screen's lobby. Carries the currently-playing item + its live position
/// into [PartyNotifier.createFromCurrentPlayback] (`party:create` pre-selects
/// the media, then a `sync:seek` restores the position), then hands off to
/// the immersive party screen — the party stays alive from here on regardless
/// of further navigation.
class _StartPartyButton extends ConsumerStatefulWidget {
  const _StartPartyButton({required this.itemId});
  final String itemId;

  @override
  ConsumerState<_StartPartyButton> createState() => _StartPartyButtonState();
}

class _StartPartyButtonState extends ConsumerState<_StartPartyButton> {
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final position = ref.read(playerControllerProvider).positionNow;
      final partyId = await ref
          .read(partyProvider.notifier)
          .createFromCurrentPlayback(
            mediaItemId: widget.itemId,
            position: position,
          );
      if (!mounted) return;
      context.go('/party/$partyId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start a party: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Already in a party (e.g. re-entering solo playback from elsewhere) —
    // nothing to start.
    if (ref.watch(partyProvider) != null) return const SizedBox.shrink();
    return AppButton(
      label: 'Start party',
      icon: Icons.groups_outlined,
      variant: AppButtonVariant.secondary,
      busy: _busy,
      onPressed: _busy ? null : _start,
    );
  }
}
