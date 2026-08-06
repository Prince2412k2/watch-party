import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';

/// The interaction state of a single chrome control.
///
/// Kept as a value so every control in the kit paints the same four states from
/// the same source, and so a widget test can assert the geometry of each one
/// without reaching into private state.
@immutable
class AnalogControlState {
  const AnalogControlState({
    required this.enabled,
    required this.hovered,
    required this.focused,
    required this.pressed,
  });

  final bool enabled;
  final bool hovered;
  final bool focused;
  final bool pressed;

  /// The control has been reached — by pointer, by keyboard, or by a press in
  /// flight. Brightens ink and hairlines. Never the *only* signal for anything:
  /// focus additionally draws a ring, selection additionally draws a detent,
  /// and a press additionally sinks the surface.
  bool get lit => enabled && (hovered || focused || pressed);
}

typedef AnalogControlBuilder =
    Widget Function(BuildContext context, AnalogControlState state);

/// The pointer/keyboard/focus plumbing every chrome control in this kit sits
/// on.
///
/// Routing all of them through one widget is what makes the reference's "No
/// hover-only controls" guardrail structural rather than a habit: anything
/// built on [AnalogPressable] takes focus, activates on Enter/Space/Select,
/// reports itself to [Semantics], and refuses all three when disabled.
///
/// It paints nothing. The caller's [builder] owns every pixel, so the same
/// interaction contract backs a button, a chip, a switch and a menu row without
/// any of them inheriting a look they did not ask for.
class AnalogPressable extends StatefulWidget {
  const AnalogPressable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onSecondaryPressed,
    this.semanticLabel,
    this.selected,
    this.toggled,
    this.button = true,
    this.autofocus = false,
    this.focusNode,
    this.cursor = SystemMouseCursors.click,
    this.excludeSemantics = false,
  });

  final AnalogControlBuilder builder;

  /// A null callback is the disabled state — focus, hover, keys and pointer all
  /// go quiet together, so there is no way to reach a control that cannot act.
  final VoidCallback? onPressed;

  /// Right-click / long-press, for controls that also carry a context menu.
  final void Function(Offset globalPosition)? onSecondaryPressed;

  final String? semanticLabel;

  /// `Semantics.selected` — a radio-ish control that is one of several.
  final bool? selected;

  /// `Semantics.toggled` — a switch.
  final bool? toggled;

  final bool button;
  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor cursor;

  /// Set when the caller supplies richer semantics of its own around the
  /// control and does not want the children announced twice.
  final bool excludeSemantics;

  @override
  State<AnalogPressable> createState() => _AnalogPressableState();
}

class _AnalogPressableState extends State<AnalogPressable> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void didUpdateWidget(AnalogPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabling a control mid-interaction must not leave it stuck looking hot.
    if (!_enabled && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  void _set(void Function() mutate) {
    if (!mounted) return;
    setState(mutate);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    final activator =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;
    if (!activator) return KeyEventResult.ignored;

    // Down sinks the surface and up fires, so a held key reads the same as a
    // held pointer rather than repeating.
    if (event is KeyDownEvent) {
      _set(() => _pressed = true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _set(() => _pressed = false);
      widget.onPressed?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = AnalogControlState(
      enabled: _enabled,
      hovered: _hovered,
      focused: _focused,
      pressed: _pressed,
    );

    Widget child = widget.builder(context, state);

    child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: _enabled ? (_) => _set(() => _pressed = true) : null,
      onTapUp: _enabled ? (_) => _set(() => _pressed = false) : null,
      onTapCancel: _enabled ? () => _set(() => _pressed = false) : null,
      onSecondaryTapDown: widget.onSecondaryPressed == null
          ? null
          : (details) => widget.onSecondaryPressed!(details.globalPosition),
      onLongPressStart: widget.onSecondaryPressed == null
          ? null
          : (details) => widget.onSecondaryPressed!(details.globalPosition),
      child: child,
    );

    child = MouseRegion(
      cursor: _enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: _enabled ? (_) => _set(() => _hovered = true) : null,
      onExit: (_) => _set(() => _hovered = false),
      child: child,
    );

    child = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: _enabled,
      descendantsAreFocusable: false,
      onKeyEvent: _onKey,
      onFocusChange: (has) => _set(() => _focused = has),
      child: child,
    );

    return Semantics(
      container: true,
      button: widget.button,
      enabled: _enabled,
      selected: widget.selected,
      toggled: widget.toggled,
      focusable: _enabled,
      focused: _focused,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeSemantics,
      onTap: widget.onPressed,
      child: child,
    );
  }
}

/// The keyboard-focus mark shared by the whole kit.
///
/// A ring, not a tint. "Selection must not rely on color alone" is written for
/// the browse stage but applies with more force to chrome, where a focused and
/// an unfocused button are otherwise the same rectangle — and where a user on a
/// remote has nothing but this to tell them where they are.
///
/// Drawn *inside* the control's bounds rather than around them: an outer ring
/// is prettier but disappears the moment an ancestor clips, and chrome sits in
/// clipped rows all over this app.
class AnalogFocusRing extends StatelessWidget {
  const AnalogFocusRing({
    super.key,
    required this.visible,
    required this.child,
    this.radius = AnalogRadius.chromePx,
    this.inset = 3.0,
  });

  final bool visible;
  final Widget child;
  final double radius;
  final double inset;

  @override
  Widget build(BuildContext context) {
    if (!visible) return child;
    return CustomPaint(
      foregroundPainter: _FocusRingPainter(radius: radius, inset: inset),
      child: child,
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.radius, required this.inset});

  final double radius;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      inset,
      inset,
      (size.width - inset * 2).clamp(0.0, double.infinity),
      (size.height - inset * 2).clamp(0.0, double.infinity),
    );
    if (rect.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AnalogPoster.framePx
      ..color = AnalogColor.ink;
    final r = (radius - inset).clamp(0.0, radius);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), paint);
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.radius != radius || old.inset != inset;
}
