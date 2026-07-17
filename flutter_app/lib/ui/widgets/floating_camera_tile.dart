import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../livekit/livekit_room.dart';
import '../../state/livekit_provider.dart';
import '../tokens.dart';
import 'camera_grid.dart';

/// Pure layout math for the floating PiP tiles — kept free of widgets so the
/// clamp / cascade / resize rules can be unit-tested directly.
///
/// Tiles keep a fixed ~4:3 camera aspect ratio, honour a sensible min/max
/// width, and are always clamped so they can never be dragged (or stranded by
/// a window resize) fully off the video stage.
abstract final class FloatingTileGeometry {
  /// Camera aspect ratio (width : height).
  static const double aspect = 4 / 3;

  static const double minWidth = 112;
  static const double maxWidth = 340;

  /// Height of a collapsed tile — just its chrome header.
  static const double headerHeight = 26;

  /// Inset from the stage edges for the first-show cascade + edge snap.
  static const double margin = AppSpacing.md;

  /// Distance (px) from an edge within which a drag-end snaps to that edge.
  static const double snap = 18;

  static const double defaultWidth = 168;

  /// Full pixel size of a tile given its width and collapsed state.
  static Size tileSize(double width, {required bool collapsed}) =>
      Size(width, collapsed ? headerHeight : headerHeight + width / aspect);

  /// Clamp a width to the min/max, also never wider than the stage allows.
  static double clampWidth(double width, Size stage) {
    final cap = math.min(
      maxWidth,
      math.max(minWidth, stage.width - 2 * margin),
    );
    return width.clamp(minWidth, cap);
  }

  /// Clamp a top-left [offset] so a tile of [tile] size stays within [stage].
  /// If the stage is smaller than the tile in a dimension the tile pins to 0.
  static Offset clamp(Offset offset, Size tile, Size stage) => Offset(
    offset.dx.clamp(0.0, math.max(0.0, stage.width - tile.width)),
    offset.dy.clamp(0.0, math.max(0.0, stage.height - tile.height)),
  );

  /// Default first-show position for the tile at [index]: anchored to the
  /// bottom-right and stacked upward so tiles don't start life overlapping.
  static Offset cascadeAnchor(int index, Size tile, Size stage) {
    final left = stage.width - tile.width - margin;
    final top =
        stage.height -
        margin -
        (index + 1) * tile.height -
        index * AppSpacing.sm;
    return clamp(Offset(left, top), tile, stage);
  }

  /// Snap a clamped [offset] to the nearest stage edge when within [snap].
  static Offset snapToEdges(Offset offset, Size tile, Size stage) {
    var dx = offset.dx;
    var dy = offset.dy;
    final maxX = math.max(0.0, stage.width - tile.width);
    final maxY = math.max(0.0, stage.height - tile.height);
    if (dx <= margin + snap) dx = margin.clamp(0.0, maxX);
    if (dx >= maxX - margin - snap) dx = (maxX - margin).clamp(0.0, maxX);
    if (dy <= margin + snap) dy = margin.clamp(0.0, maxY);
    if (dy >= maxY - margin - snap) dy = (maxY - margin).clamp(0.0, maxY);
    return Offset(dx, dy);
  }
}

/// Per-tile mutable layout state held by [FloatingCameraLayer].
class _TileLayout {
  _TileLayout(this.offset, this.width);
  Offset offset;
  double width;
  bool collapsed = false;
}

/// Overlay that renders each LiveKit participant as a floating, draggable and
/// resizable PiP window on top of the video stage. Areas not covered by a tile
/// stay transparent to pointer events, so the movie player underneath keeps
/// receiving taps — the tiles never permanently obscure the video.
///
/// Mount it as the top child of a [Stack] over the player (e.g. via
/// `Positioned.fill`); it sizes itself to the stage and clamps every tile to
/// those bounds, re-clamping on window resize. Drag-end snap and collapse are
/// animated ([AnimatedPositioned] with a spring curve); live drag/resize follow
/// the pointer instantly.
class FloatingCameraLayer extends ConsumerStatefulWidget {
  const FloatingCameraLayer({super.key});

  @override
  ConsumerState<FloatingCameraLayer> createState() =>
      _FloatingCameraLayerState();
}

class _FloatingCameraLayerState extends ConsumerState<FloatingCameraLayer> {
  final Map<String, _TileLayout> _layouts = {};
  Size _stage = Size.zero;

  /// Whether position/size changes should animate. False while the pointer is
  /// actively dragging/resizing (instant follow), true for snap + collapse.
  bool _animate = false;

  @override
  Widget build(BuildContext context) {
    final lkState = ref.watch(livekitProvider);
    final tiles = lkState.tracks
        .where((t) => !(t.isLocal && lkState.hideSelf))
        .toList(growable: false);

    if (!lkState.connected || tiles.isEmpty) {
      return const SizedBox.shrink();
    }

    // Drop layouts for participants who have left.
    final live = tiles.map((t) => t.identity).toSet();
    _layouts.removeWhere((id, _) => !live.contains(id));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        _stage = Size(constraints.maxWidth, constraints.maxHeight);

        final children = <Widget>[];
        for (var i = 0; i < tiles.length; i++) {
          final track = tiles[i];
          final layout = _layouts.putIfAbsent(track.identity, () {
            final w = FloatingTileGeometry.clampWidth(
              FloatingTileGeometry.defaultWidth,
              _stage,
            );
            final size = FloatingTileGeometry.tileSize(w, collapsed: false);
            return _TileLayout(
              FloatingTileGeometry.cascadeAnchor(i, size, _stage),
              w,
            );
          });

          final width = FloatingTileGeometry.clampWidth(layout.width, _stage);
          layout.width = width;
          final size = FloatingTileGeometry.tileSize(
            width,
            collapsed: layout.collapsed,
          );
          final pos = FloatingTileGeometry.clamp(layout.offset, size, _stage);

          children.add(
            AnimatedPositioned(
              duration: _animate ? AppMotion.snap : Duration.zero,
              curve: AppMotion.spring,
              left: pos.dx,
              top: pos.dy,
              width: size.width,
              height: size.height,
              child: FloatingCameraTile(
                key: ValueKey('floating-cam-${track.identity}'),
                track: track,
                collapsed: layout.collapsed,
                onDrag: (delta) => _onDrag(track.identity, delta),
                onDragEnd: () => _onDragEnd(track.identity),
                onResize: (delta) => _onResize(track.identity, delta),
                onToggleCollapse: () => _toggleCollapse(track.identity),
              ),
            ),
          );
        }

        return Stack(children: children);
      },
    );
  }

  Size _sizeOf(_TileLayout l) =>
      FloatingTileGeometry.tileSize(l.width, collapsed: l.collapsed);

  void _onDrag(String id, Offset delta) {
    final l = _layouts[id];
    if (l == null) return;
    setState(() {
      _animate = false;
      l.offset = FloatingTileGeometry.clamp(
        l.offset + delta,
        _sizeOf(l),
        _stage,
      );
    });
  }

  void _onDragEnd(String id) {
    final l = _layouts[id];
    if (l == null) return;
    setState(() {
      _animate = true;
      l.offset = FloatingTileGeometry.snapToEdges(l.offset, _sizeOf(l), _stage);
    });
  }

  void _onResize(String id, Offset delta) {
    final l = _layouts[id];
    if (l == null) return;
    setState(() {
      _animate = false;
      l.width = FloatingTileGeometry.clampWidth(l.width + delta.dx, _stage);
      l.offset = FloatingTileGeometry.clamp(l.offset, _sizeOf(l), _stage);
    });
  }

  void _toggleCollapse(String id) {
    final l = _layouts[id];
    if (l == null) return;
    setState(() {
      _animate = true;
      l.collapsed = !l.collapsed;
      l.offset = FloatingTileGeometry.clamp(l.offset, _sizeOf(l), _stage);
    });
  }
}

/// A single **frameless** floating PiP camera window. The participant's video
/// fills the whole tile (rounded corners only) and the ENTIRE tile is draggable.
/// Chrome — a subtle top scrim with the name + mic/speaking indicator, the
/// local mic/cam/hide mini-controls, the collapse toggle and the bottom-right
/// resize handle — fades in only on hover (or while speaking) and fades out
/// otherwise. Speaking shows a subtle [AppColors.live] glow ring, not a plate.
///
/// Position/size are owned by the parent [FloatingCameraLayer]; this widget
/// just reports drag/resize deltas via callbacks. The public constructor
/// signature is frozen.
class FloatingCameraTile extends StatefulWidget {
  const FloatingCameraTile({
    super.key,
    required this.track,
    required this.collapsed,
    required this.onDrag,
    required this.onDragEnd,
    required this.onResize,
    required this.onToggleCollapse,
  });

  final ParticipantTrack track;
  final bool collapsed;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<Offset> onResize;
  final VoidCallback onToggleCollapse;

  @override
  State<FloatingCameraTile> createState() => _FloatingCameraTileState();
}

class _FloatingCameraTileState extends State<FloatingCameraTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final speaking = track.isSpeaking;
    final showChrome = _hover || speaking || widget.collapsed;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);

    final body = widget.collapsed
        // Collapsed: no video, just a compact strip carrying the chrome
        // (name + expand toggle). The whole strip still drags.
        ? ColoredBox(
            color: AppColors.surface,
            child: _TopChrome(
              track: track,
              collapsed: true,
              onToggleCollapse: widget.onToggleCollapse,
            ),
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              CameraVideoView(track: track),
              // Top scrim + name/indicators/collapse — hover/speaking only.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: AnimatedOpacity(
                  opacity: showChrome ? 1 : 0,
                  duration: AppMotion.hover,
                  child: _TopChrome(
                    track: track,
                    collapsed: false,
                    onToggleCollapse: widget.onToggleCollapse,
                  ),
                ),
              ),
              if (track.isLocal)
                Positioned(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: AnimatedOpacity(
                    opacity: showChrome ? 1 : 0,
                    duration: AppMotion.hover,
                    child: const _LocalTileControls(),
                  ),
                ),
            ],
          );

    // The whole tile drags (frameless — no header bar). The resize handle is a
    // sibling STACKED ABOVE this drag layer, not a descendant, so its pan wins
    // the gesture arena when the pointer starts on it.
    final draggable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => widget.onDrag(d.delta),
      onPanEnd: (_) => widget.onDragEnd(),
      child: AnimatedContainer(
        duration: AppMotion.hover,
        decoration: BoxDecoration(
          borderRadius: radius,
          // Subtle glow ring when speaking (no heavy border/plate).
          boxShadow: speaking
              ? [
                  BoxShadow(
                    color: AppColors.live.withValues(alpha: 0.55),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : AppElevation.high,
        ),
        child: ClipRRect(borderRadius: radius, child: body),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.move,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          Positioned.fill(child: draggable),
          if (!widget.collapsed)
            Positioned(
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: showChrome ? 1 : 0,
                duration: AppMotion.hover,
                child: _ResizeHandle(onResize: widget.onResize),
              ),
            ),
        ],
      ),
    );
  }
}

/// The top hover-chrome: a soft gradient scrim carrying a drag affordance, mic/
/// speaking indicators, the participant name, and the collapse/expand toggle.
class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.track,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final ParticipantTrack track;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final label = track.isLocal ? '${track.name} (you)' : track.name;
    return Container(
      height: FloatingTileGeometry.headerHeight,
      padding: const EdgeInsets.only(left: 4, right: 2),
      decoration: collapsed
          ? null
          : const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 14, color: AppColors.faint),
          const SizedBox(width: 2),
          if (track.audioMuted)
            const Padding(
              padding: EdgeInsets.only(right: 3),
              child: Icon(Icons.mic_off, size: 12, color: AppColors.dim),
            ),
          if (track.isSpeaking)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(
                color: AppColors.live,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _HeaderButton(
            icon: collapsed ? Icons.open_in_full : Icons.minimize,
            tooltip: collapsed ? 'Expand tile' : 'Collapse tile',
            onTap: onToggleCollapse,
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 13, color: AppColors.dim),
        ),
      ),
    );
  }
}

/// Compact mic/cam/hide-self toggles for the local participant's floating
/// tile. Reads/writes the same [livekitProvider] as the docked [MicCamControls]
/// so the two stay in sync.
class _LocalTileControls extends ConsumerWidget {
  const _LocalTileControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lkState = ref.watch(livekitProvider);
    final notifier = ref.read(livekitProvider.notifier);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniToggle(
              icon: lkState.micEnabled ? Icons.mic : Icons.mic_off,
              active: lkState.micEnabled,
              tooltip: lkState.micEnabled
                  ? 'Mute microphone'
                  : 'Unmute microphone',
              onTap: () => notifier.setMic(!lkState.micEnabled),
            ),
            _MiniToggle(
              icon: lkState.cameraEnabled ? Icons.videocam : Icons.videocam_off,
              active: lkState.cameraEnabled,
              tooltip: lkState.cameraEnabled
                  ? 'Turn camera off'
                  : 'Turn camera on',
              onTap: () => notifier.setCamera(!lkState.cameraEnabled),
            ),
            _MiniToggle(
              icon: lkState.hideSelf ? Icons.visibility_off : Icons.visibility,
              active: !lkState.hideSelf,
              tooltip: lkState.hideSelf ? 'Show my tile' : 'Hide my tile',
              onTap: () => notifier.setHideSelf(!lkState.hideSelf),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 15,
            color: active ? AppColors.text : AppColors.faint,
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onResize});

  final ValueChanged<Offset> onResize;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onResize(d.delta),
        child: Container(
          width: 20,
          height: 20,
          color: const Color(0x66000000),
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.only(right: 2, bottom: 2),
          child: const Icon(Icons.south_east, size: 12, color: AppColors.dim),
        ),
      ),
    );
  }
}
