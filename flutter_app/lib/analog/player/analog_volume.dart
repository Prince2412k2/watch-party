// The analog volume control: a compact VERTICAL hairline near the right edge,
// replacing the 76px horizontal slider that used to sit in the bottom
// transport row.
//
// "The volume track follows the same hairline treatment and preserves mute,
// previous-volume restore, keyboard adjustment, and a sufficiently large touch
// target." (docs/watchparty-design/player-interface-reference.md)
//
// Previous-volume restore lives in the player chrome (it owns the pre-mute
// level); this widget owns the gesture, the keyboard and the paint.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/analog_tokens.dart';

/// How much one arrow key moves the level, on the 0..100 media_kit scale.
const double kAnalogVolumeKeyStep = 10;

class AnalogVolume extends StatefulWidget {
  const AnalogVolume({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
    this.trackKey,
    this.trackLength = 96,
    this.onAdjustingChanged,
  });

  /// 0..100 (media_kit's scale).
  final double volume;
  final ValueChanged<double> onChanged;

  /// Mute/unmute. The caller restores the pre-mute level, so this control never
  /// has to remember one.
  final VoidCallback onToggleMute;

  /// Key placed on the draggable track itself.
  final Key? trackKey;

  final double trackLength;

  /// Raised for the length of a drag so the caller can pin the chrome open.
  final ValueChanged<bool>? onAdjustingChanged;

  @override
  State<AnalogVolume> createState() => _AnalogVolumeState();
}

class _AnalogVolumeState extends State<AnalogVolume> {
  final _focusNode = FocusNode(debugLabel: 'AnalogVolume');

  bool _hovering = false;
  bool _focused = false;
  bool _dragging = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _level => widget.volume.clamp(0.0, 100.0);

  /// Up is louder: the fraction is measured from the BOTTOM of the track. [dy]
  /// is local to the gesture detector, which is exactly the track box — the
  /// mute button below it is a sibling and must not enter the arithmetic.
  double _fractionAt(double dy) {
    if (widget.trackLength <= 0) return 0;
    return (1 - dy / widget.trackLength).clamp(0.0, 1.0);
  }

  void _setAdjusting(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
    widget.onAdjustingChanged?.call(value);
  }

  void _emit(double fraction) => widget.onChanged(fraction * 100);

  void _nudge(double delta) =>
      widget.onChanged((_level + delta).clamp(0.0, 100.0));

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // A held Ctrl/Meta belongs to the platform, never to this control.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _nudge(kAnalogVolumeKeyStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _nudge(-kAnalogVolumeKeyStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        widget.onChanged(100);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        widget.onChanged(0);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final muted = _level <= 0;
    final active = _hovering || _focused || _dragging;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          focusNode: _focusNode,
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: _onKey,
          child: Semantics(
            slider: true,
            label: 'Volume',
            // The framework requires value/increasedValue/decreasedValue to
            // travel together with the increase/decrease actions.
            value: '${_level.round()}%',
            increasedValue:
                '${(_level + kAnalogVolumeKeyStep).clamp(0, 100).round()}%',
            decreasedValue:
                '${(_level - kAnalogVolumeKeyStep).clamp(0, 100).round()}%',
            onIncrease: () => _nudge(kAnalogVolumeKeyStep),
            onDecrease: () => _nudge(-kAnalogVolumeKeyStep),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  // Clicking the track takes focus, so the arrow keys go to
                  // this control rather than the player's global keymap.
                  _focusNode.requestFocus();
                  _emit(_fractionAt(details.localPosition.dy));
                },
                onVerticalDragStart: (details) {
                  _focusNode.requestFocus();
                  _setAdjusting(true);
                  _emit(_fractionAt(details.localPosition.dy));
                },
                onVerticalDragUpdate: (details) =>
                    _emit(_fractionAt(details.localPosition.dy)),
                onVerticalDragEnd: (_) => _setAdjusting(false),
                onVerticalDragCancel: () => _setAdjusting(false),
                // hitPx wide, so the visible 2px line keeps a touch-sized
                // target without widening the column.
                child: SizedBox(
                  key: widget.trackKey,
                  width: AnalogHairline.hitPx,
                  height: widget.trackLength,
                  child: CustomPaint(
                    painter: AnalogVolumePainter(
                      fraction: _level / 100,
                      active: active,
                      focused: _focused && !_hovering && !_dragging,
                      showHandle: active,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Tooltip(
          message: muted ? 'Unmute' : 'Mute',
          child: IconButton(
            onPressed: widget.onToggleMute,
            icon: Icon(
              muted
                  ? Icons.volume_off
                  : (_level < 50 ? Icons.volume_down : Icons.volume_up),
              size: 20,
            ),
            color: AnalogColor.inkDim,
            splashRadius: 20,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
        ),
      ],
    );
  }
}

/// Vertical twin of [AnalogTimelinePainter]: same hairline widths, same layer
/// strengths, filled from the bottom up.
class AnalogVolumePainter extends CustomPainter {
  const AnalogVolumePainter({
    required this.fraction,
    required this.active,
    required this.focused,
    required this.showHandle,
  });

  final double fraction;
  final bool active;
  final bool focused;
  final bool showHandle;

  static Rect trackRect(Size size, {required bool active}) {
    final width = active ? AnalogHairline.activePx : AnalogHairline.idlePx;
    final left = (size.width - width) / 2;
    return Rect.fromLTWH(left, 0, width, size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    final track = trackRect(size, active: active);
    final radius = Radius.circular(track.width / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = AnalogColor.line,
    );

    final filled = fraction.clamp(0.0, 1.0) * track.height;
    if (filled > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            track.left,
            track.bottom - filled,
            track.width,
            filled,
          ),
          radius,
        ),
        Paint()..color = AnalogColor.accent,
      );
    }

    if (!showHandle) return;
    final centre = Offset(size.width / 2, track.bottom - filled);
    canvas.drawCircle(
      centre,
      AnalogHairline.handlePx / 2,
      Paint()..color = AnalogColor.accent,
    );
    if (focused) {
      canvas.drawCircle(
        centre,
        AnalogHairline.handleFocusPx / 2,
        Paint()
          ..color = AnalogColor.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(AnalogVolumePainter old) =>
      old.fraction != fraction ||
      old.active != active ||
      old.focused != focused ||
      old.showHandle != showHandle;
}
