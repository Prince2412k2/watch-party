import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:window_manager/window_manager.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../player/offline_playback.dart';
import '../../player/player_view.dart';
import '../../state/offline_provider.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import 'detail_stage.dart';

/// Title-detail screen. For an authenticated user this is the fullscreen
/// cinematic [DetailStage] (movie / show / episode); a logged-out guest gets a
/// minimal offline-only body sourced from the on-device manifest. Watching
/// hands the play target + selected audio/subtitle indices into the solo player
/// route; the mid-movie "Start party" affordance stays wired over playback.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;

    // Guest offline-browse (PLAN §E): a logged-out user has no Jellyfin
    // session, so their detail view is sourced entirely from the offline
    // manifest and goes straight to local playback — never touching the network.
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    if (!isAuthenticated) {
      final offline = ref.watch(offlineProvider);
      OfflineRecord? record;
      for (final r in offline) {
        if (r.itemId == itemId) {
          record = r;
          break;
        }
      }
      return Scaffold(
        backgroundColor: wp.bg,
        body: SafeArea(
          child: record == null
              ? EmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Not available offline',
                  message: 'Sign in to browse and download this title.',
                  actionLabel: 'Login',
                  onAction: () => context.go('/login'),
                )
              : _GuestOfflineDetailBody(record: record),
        ),
      );
    }

    return Scaffold(
      backgroundColor: wp.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DetailStage(
              itemId: itemId,
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/movies'),
              onWatch: (playItem, tracks) async {
                final party = ref.read(partyProvider);
                if (party != null) {
                  final notifier = ref.read(partyProvider.notifier);
                  if (notifier.canControl) {
                    await notifier.selectMedia(
                      playItem.id,
                      audioStreamIndex: tracks.audioStreamIndex,
                      subtitleStreamIndex: tracks.subtitleStreamIndex,
                    );
                  }
                  if (context.mounted) context.go('/party/${party.id}');
                  return;
                }
                await Navigator.of(context).push(
                  _playerRouteFor(
                    itemId: playItem.id,
                    audioStreamIndex: tracks.audioStreamIndex,
                    subtitleStreamIndex: tracks.subtitleStreamIndex,
                  ),
                );
              },
            ),
          ),
          const Positioned(right: 22, bottom: 18, child: PopcornControl()),
        ],
      ),
    );
  }
}

/// A guest's detail view for a downloaded title — no server, no session, just
/// what's already on disk (PLAN §E).
class _GuestOfflineDetailBody extends StatelessWidget {
  const _GuestOfflineDetailBody({required this.record});
  final OfflineRecord record;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final runtime = record.runTimeTicks > 0
        ? '${(record.runTimeTicks / 600000000).round()}m'
        : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          sc.IconButton.ghost(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/movies'),
            icon: Icon(Icons.arrow_back, color: wp.dim),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            record.title,
            style: AppTheme.displaySmall.copyWith(color: wp.text),
          ),
          if (runtime != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(runtime, style: AppTheme.mono.copyWith(color: wp.dim)),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Play',
            icon: Icons.play_arrow,
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(
              context,
            ).push(_playerRouteFor(itemId: record.itemId)),
          ),
        ],
      ),
    );
  }
}

/// Fade transition into the solo player (per the redesign's motion system).
/// [audioStreamIndex]/[subtitleStreamIndex] carry the detail-stage track
/// selection through to playback (web `onWatch(item, tracks)`).
Route<void> _playerRouteFor({
  required String itemId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: AppMotion.page,
    reverseTransitionDuration: AppMotion.page,
    pageBuilder: (context, animation, secondaryAnimation) => _SoloPlayer(
      itemId: itemId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    ),
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

/// Solo playback launcher for the detail screen. Opens the shared
/// [playerControllerProvider] preferring a locally-downloaded copy over the
/// network stream (E8.3 `openPreferringOffline`), then mounts the real E4.2
/// [PlayerView] chrome.
class _SoloPlayer extends ConsumerStatefulWidget {
  const _SoloPlayer({
    required this.itemId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });
  final String itemId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  @override
  ConsumerState<_SoloPlayer> createState() => _SoloPlayerState();
}

class _SoloPlayerState extends ConsumerState<_SoloPlayer> {
  Object? _error;
  bool _ready = false;
  bool _isFullscreen = false;
  bool _exiting = false;
  bool _allowPop = false;
  bool _popping = false;
  bool _handoffToParty = false;
  Future<void>? _openFuture;

  bool _usesCacheProxy = false;

  // Capture the shared, provider-owned controller once so dispose() can pause
  // it WITHOUT touching `ref`.
  late final _controller = ref.read(playerControllerProvider);

  @override
  void initState() {
    super.initState();
    _controller; // force initialization here, where ref.read is valid
    _openFuture = _open();
  }

  @override
  void dispose() {
    unawaited(_stopPlayback());
    if (_isFullscreen) unawaited(windowManager.setFullScreen(false));
    super.dispose();
  }

  Future<void> _stopPlayback() async {
    if (_handoffToParty) return;
    _exiting = true;
    try {
      await _openFuture;
    } catch (_) {}
    await _controller.pause();
    await _controller.seek(Duration.zero);
    if (_isFullscreen) await windowManager.setFullScreen(false);
  }

  Future<void> _exit() async {
    if (_popping) return;
    _popping = true;
    await _stopPlayback();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await Navigator.of(context).maybePop();
  }

  void _retry() {
    _exiting = false;
    _popping = false;
    _openFuture = _open();
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
      final isAuthenticated = ref.read(
        authProvider.select((s) => s.isAuthenticated),
      );
      // Pre-select the audio/subtitle tracks the detail stage picked, so the
      // stream the cache proxy mints delivers them (web `onWatch(tracks)` →
      // playback-info selection). Best-effort: a failure here must not block
      // playback, so swallow it and open with the server defaults.
      if (isAuthenticated &&
          (widget.audioStreamIndex != null ||
              widget.subtitleStreamIndex != null)) {
        try {
          await ref
              .read(apiClientProvider)
              .playbackInfo(
                widget.itemId,
                audioStreamIndex: widget.audioStreamIndex,
                subtitleStreamIndex: widget.subtitleStreamIndex,
              );
        } catch (_) {}
      }
      // Routed through the on-device caching proxy instead of a direct signed
      // URL — it mints/re-mints one itself on demand.
      final streamUrl = isAuthenticated
          ? ref.read(mediaCacheProxyProvider).urlFor(widget.itemId)
          : '';
      _usesCacheProxy = isAuthenticated;
      await openPreferringOffline(
        ref,
        _controller,
        itemId: widget.itemId,
        streamUrl: streamUrl,
        autoplay: false,
      );
      if (_exiting || !mounted) {
        await _controller.pause();
        return;
      }
      await _controller.play();
      if (_exiting || !mounted) {
        await _controller.pause();
        return;
      }
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? Center(
                child: ErrorState(
                  title: 'Playback failed',
                  message: _error is ApiException
                      ? (_error as ApiException).message
                      : 'Could not open this title. Check your connection and try again.',
                  onRetry: _retry,
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
                    onToggleFullscreen: _toggleFullscreen,
                    isFullscreen: _isFullscreen,
                    cachedSpans: _usesCacheProxy
                        ? ref
                              .watch(mediaCacheProxyProvider)
                              .cachedSpansFor(widget.itemId)
                        : null,
                  ),
                  Positioned(
                    top: _isFullscreen ? 8 : integratedDesktopChromeHeight + 8,
                    left: 8 + (_isFullscreen ? 0 : desktopLeadingControlInset),
                    right:
                        8 + (_isFullscreen ? 0 : desktopTrailingControlInset),
                    child: SafeArea(
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: _exit,
                            icon: const Icon(Icons.arrow_back),
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.black54,
                            ),
                          ),
                          const Spacer(),
                          _StartPartyButton(
                            itemId: widget.itemId,
                            audioStreamIndex: widget.audioStreamIndex,
                            subtitleStreamIndex: widget.subtitleStreamIndex,
                            onHandoff: () => _handoffToParty = true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Start a party" affordance floated over solo playback, so a party can be
/// spun up MID-MOVIE. Carries the currently-playing item + its live position
/// into [PartyNotifier.createFromCurrentPlayback], then hands off to the
/// immersive party screen.
class _StartPartyButton extends ConsumerStatefulWidget {
  const _StartPartyButton({
    required this.itemId,
    required this.onHandoff,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });
  final String itemId;
  final VoidCallback onHandoff;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

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
            audioStreamIndex: widget.audioStreamIndex,
            subtitleStreamIndex: widget.subtitleStreamIndex,
          );
      if (!mounted) return;
      widget.onHandoff();
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
    final isAuthenticated = ref.watch(
      authProvider.select((s) => s.isAuthenticated),
    );
    if (!isAuthenticated || ref.watch(partyProvider) != null) {
      return const SizedBox.shrink();
    }
    return AppButton(
      label: 'Start party',
      icon: Icons.groups_outlined,
      variant: AppButtonVariant.secondary,
      busy: _busy,
      onPressed: _busy ? null : _start,
    );
  }
}
