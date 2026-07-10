import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../ui/tokens.dart';
import '../ui/widgets/error_state.dart';
import 'media_kit_player_controller.dart';
import 'player_chrome.dart';
import 'player_controller.dart';
import 'video_view.dart';

/// Composes [VideoView] + [PlayerChrome] into the single embeddable playback
/// widget (PLAN §4 E4.2/E4.3). This is the widget E3 (title detail — solo
/// play) and E5 (watch party) mount; both own their [PlayerController]
/// lifecycle in the party/detail case, or hand this widget an itemId to
/// resolve+own one itself in the solo case.
///
/// Two ways to use it:
///  * `PlayerView(controller: myController)` — caller already opened a
///    [PlayerController] (party screen: the controller is shared with
///    `SyncEngine`; detail screen: a controller opened ahead of time).
///    `PlayerView` does NOT dispose a controller it didn't create.
///  * `PlayerView.item(itemId, apiClient: client)` — convenience constructor:
///    resolves `native/stream-url` and opens a fresh
///    [MediaKitPlayerController] itself, autoplaying by default. `PlayerView`
///    owns and disposes this controller.
class PlayerView extends StatefulWidget {
  const PlayerView({
    super.key,
    required PlayerController controller,
    this.canControl = true,
    this.title,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.onSeek,
  })  : _controller = controller,
        _itemId = null,
        _apiClient = null,
        _purpose = 'stream',
        _startAt = Duration.zero,
        _autoplay = true;

  /// Resolves `itemId` via [apiClient.nativeStreamUrl] and opens a fresh
  /// [MediaKitPlayerController] internally; disposed when this widget is
  /// disposed. Use for solo playback (E3 title detail) where no external
  /// owner (e.g. the party's `SyncEngine`) needs the controller.
  const PlayerView.item(
    String itemId, {
    super.key,
    required ApiClient apiClient,
    this.canControl = true,
    this.title,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    Duration startAt = Duration.zero,
    bool autoplay = true,
    String purpose = 'stream',
  })  : _controller = null,
        _itemId = itemId,
        _apiClient = apiClient,
        _purpose = purpose,
        _startAt = startAt,
        _autoplay = autoplay,
        onSeek = null;

  /// Ready-made controller supplied by the caller (party/detail inject one).
  /// Null when using [PlayerView.item].
  final PlayerController? _controller;

  final String? _itemId;
  final ApiClient? _apiClient;
  final String _purpose;
  final Duration _startAt;
  final bool _autoplay;

  /// Read-only transport bar when false — E5 passes this for a guest without
  /// playback-control rights (PLAN §4 E5.2 `canControl` gating).
  final bool canControl;

  /// Optional title shown in the chrome's top bar.
  final String? title;

  /// Optional back affordance in the chrome's top bar.
  final VoidCallback? onBack;

  /// Fullscreen is a window-level concern owned by the caller; chrome only
  /// renders the affordance and calls this.
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  /// Authors a seek to an external owner (the party's sync engine). Only set on
  /// the party path; null for solo playback. Passed straight to [PlayerChrome].
  final ValueChanged<Duration>? onSeek;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  PlayerController? _ownedController;
  Object? _resolveError;
  bool _resolving = false;

  bool get _ownsController => widget._controller == null;

  PlayerController? get _activeController => widget._controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    if (_ownsController) {
      _resolveAndOpen();
    }
  }

  Future<void> _resolveAndOpen() async {
    final itemId = widget._itemId;
    final apiClient = widget._apiClient;
    if (itemId == null || apiClient == null) {
      throw StateError('PlayerView.item requires itemId + apiClient');
    }
    setState(() {
      _resolving = true;
      _resolveError = null;
    });
    try {
      final streamUrl = await apiClient.nativeStreamUrl(itemId, purpose: widget._purpose);
      final controller = MediaKitPlayerController();
      await controller.open(streamUrl.url, startAt: widget._startAt, autoplay: widget._autoplay);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _ownedController = controller;
        _resolving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolveError = e;
        _resolving = false;
      });
    }
  }

  @override
  void dispose() {
    // Only tear down a controller PlayerView itself opened — a controller
    // handed in by the caller (party/detail) is theirs to dispose.
    if (_ownsController) {
      _ownedController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _activeController;

    if (_resolveError != null) {
      return ColoredBox(
        color: AppColors.bg,
        child: ErrorState(
          title: 'Couldn\'t start playback',
          message: _resolveError.toString(),
          onRetry: _resolveAndOpen,
        ),
      );
    }

    if (controller == null || _resolving) {
      return const ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoView(controller: controller),
          PlayerChrome(
            controller: controller,
            canControl: widget.canControl,
            onSeek: widget.onSeek,
            title: widget.title,
            onBack: widget.onBack,
            onToggleFullscreen: widget.onToggleFullscreen,
            isFullscreen: widget.isFullscreen,
          ),
        ],
      ),
    );
  }
}
