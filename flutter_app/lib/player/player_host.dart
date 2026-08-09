// The app's ONE player, mounted above the router.
//
// Every other approach to picture-in-picture in a Flutter app ends up with two
// player widgets — a big one on the watch screen and a small one somewhere else
// — and then spends its life trying to hand state between them. That is what
// this file exists to avoid. There is a single [PlayerView] element here, and
// "expanded" versus "floating" is a rect it animates between. Because the
// element identity never changes, the video texture is never re-attached: no
// reload, no position loss, no audio gap.
//
// Mounted in `app.dart`'s `MaterialApp.builder`, which wraps the Navigator —
// the same place `AnalogToastHost` and `ChatNotifications` already live, and for
// the same reason. A route cannot own something that has to outlive routing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/now_playing_provider.dart';
import '../state/providers.dart';
import '../state/player_provider.dart';
import '../ui/tokens.dart';
import '../ui/widgets/floating_camera_tile.dart';
import 'player_view.dart';

/// Movies are 16:9, unlike the 4:3 camera tiles the geometry was written for.
const double _playerAspect = 16 / 9;

/// Starting width of the floating tile — wider than a camera, because a movie
/// at camera size is unreadable rather than merely small.
const double _defaultFloatingWidth = 300;

class PlayerHost extends ConsumerStatefulWidget {
  const PlayerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends ConsumerState<PlayerHost> {
  /// A GlobalKey, not a ValueKey, and that distinction is the whole file.
  ///
  /// Expanded and floating are genuinely different subtrees — one is a bare
  /// focus scope, the other a Material card with a drag header. A ValueKey only
  /// matches within a parent's child list, so switching modes REBUILT the
  /// player, re-attached the video texture and reloaded the media. A GlobalKey
  /// reparents the existing element instead, which is what keeps playback
  /// running across the transition.
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'app-player');

  /// Top-left of the floating tile, in stage coordinates. Null until the first
  /// layout, which is when a cascade anchor can actually be computed.
  Offset? _offset;
  double _width = _defaultFloatingWidth;

  Size _stageOf(BoxConstraints constraints) =>
      Size(constraints.maxWidth, constraints.maxHeight);

  Rect _floatingRect(Size stage) {
    final width = FloatingTileGeometry.clampWidth(
      _width,
      stage,
      aspect: _playerAspect,
    );
    final size = FloatingTileGeometry.tileSize(
      width,
      collapsed: false,
      aspect: _playerAspect,
    );
    final offset = FloatingTileGeometry.clamp(
      _offset ?? FloatingTileGeometry.cascadeAnchor(0, size, stage),
      size,
      stage,
    );
    return offset & size;
  }

  void _drag(DragUpdateDetails details, Size stage, Size tile) {
    setState(() {
      _offset = FloatingTileGeometry.clamp(
        (_offset ?? Offset.zero) + details.delta,
        tile,
        stage,
      );
    });
  }

  void _resize(DragUpdateDetails details, Size stage) {
    setState(() {
      _width = FloatingTileGeometry.clampWidth(
        _width + details.delta.dx,
        stage,
        aspect: _playerAspect,
      );
    });
  }

  void _dragEnd(Size stage, Size tile) {
    setState(() {
      _offset = FloatingTileGeometry.snapToEdges(
        FloatingTileGeometry.clamp(_offset ?? Offset.zero, tile, stage),
        tile,
        stage,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowPlayingProvider);
    final notifier = ref.read(nowPlayingProvider.notifier);

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (now.isOpen)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stage = _stageOf(constraints);
                final rect = now.isExpanded
                    ? Offset.zero & stage
                    : _floatingRect(stage);

                return Stack(
                  children: [
                    // A scrim only while expanded, so the app underneath is not
                    // showing through a full-bleed video. The floating tile
                    // deliberately has none: you are meant to keep using the
                    // app around it.
                    if (now.isExpanded)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(color: Colors.black),
                        ),
                      ),
                    AnimatedPositioned(
                      // The same snap the camera tiles use: a movie tile and
                      // a person tile should move alike.
                      duration: AppMotion.snap,
                      curve: AppMotion.emphasized,
                      left: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: _PlayerFrame(
                        expanded: now.isExpanded,
                        onMinimise: notifier.minimise,
                        onExpand: notifier.expand,
                        onClose: () => notifier.close(),
                        onDrag: (details) =>
                            _drag(details, stage, rect.size),
                        onDragEnd: () => _dragEnd(stage, rect.size),
                        onResize: (details) => _resize(details, stage),
                        child: PlayerView(
                          key: _playerKey,
                          controller: ref.watch(playerControllerProvider),
                          itemId: now.itemId,
                          mediaSourceId: now.mediaSourceId,
                          title: now.title,
                          apiClient: ref.watch(apiClientProvider),
                          preferredSubtitleStreamIndex:
                              now.subtitleStreamIndex,
                          onBack: notifier.minimise,
                          // No transport bar in a 300px tile: the chrome is
                          // laid out for a full window and overflows one.
                          // A PiP tile is a picture, and the frame around it
                          // carries the only two controls it needs.
                          visible: now.isExpanded ? null : false,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The chrome around the video: escape-to-minimise while expanded, and a drag
/// header plus expand/close buttons while floating.
class _PlayerFrame extends StatelessWidget {
  const _PlayerFrame({
    required this.expanded,
    required this.onMinimise,
    required this.onExpand,
    required this.onClose,
    required this.onDrag,
    required this.onDragEnd,
    required this.onResize,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onMinimise;
  final VoidCallback onExpand;
  final VoidCallback onClose;
  final ValueChanged<DragUpdateDetails> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<DragUpdateDetails> onResize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      // Escape minimises rather than closing. Back does the same thing through
      // the router's PopScope — both routes to "I am done looking at this"
      // land on the same behaviour, and neither stops playback.
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onMinimise,
        },
        child: Focus(autofocus: true, child: child),
      );
    }

    return Material(
      color: Colors.black,
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: FloatingTileGeometry.headerHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onDrag,
              onPanEnd: (_) => onDragEnd(),
              child: Row(
                children: [
                  const Spacer(),
                  _FrameButton(
                    icon: Icons.open_in_full,
                    tooltip: 'Back to full screen',
                    onPressed: onExpand,
                  ),
                  _FrameButton(
                    icon: Icons.close,
                    tooltip: 'Stop watching',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          // Tapping the video itself expands: the same gesture every phone
          // video app uses, and cheaper than aiming at a 26px header button.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onExpand,
                    child: AbsorbPointer(child: child),
                  ),
                ),
                // Bottom-right resize, matching the camera tiles' handle.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: onResize,
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: Icon(
                          Icons.drag_handle,
                          size: 11,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameButton extends StatelessWidget {
  const _FrameButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: FloatingTileGeometry.headerHeight,
        height: FloatingTileGeometry.headerHeight,
        child: Icon(icon, size: 14, color: Colors.white70),
      ),
    ),
  );
}
