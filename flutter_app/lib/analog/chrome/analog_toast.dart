import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';
import 'liquid_glass.dart';

/// What a transient notice is about. The tone picks a glyph *and* a colour —
/// never a colour on its own, so the difference between "joined" and "kicked"
/// survives a greyscale display.
enum AnalogToastTone { info, success, warning, danger }

extension on AnalogToastTone {
  IconData get glyph => switch (this) {
    AnalogToastTone.info => Icons.info_outline,
    AnalogToastTone.success => Icons.check_circle_outline,
    AnalogToastTone.warning => Icons.warning_amber_outlined,
    AnalogToastTone.danger => Icons.error_outline,
  };

  Color get ink => switch (this) {
    AnalogToastTone.info => AnalogColor.inkDim,
    AnalogToastTone.success => AnalogColor.statusSuccess,
    AnalogToastTone.warning => AnalogColor.statusDanger,
    AnalogToastTone.danger => AnalogColor.statusDanger,
  };

  /// The accent bar's colour. Info uses full ink rather than [ink]'s dimmed
  /// value: the bar is a 3px sliver and a 64%-alpha sliver reads as disabled.
  Color get edge => switch (this) {
    AnalogToastTone.info => AnalogColor.ink,
    _ => ink,
  };
}

/// The surface every analog toast is drawn on — the party notices raised
/// through [AnalogToastHost] and the chat toasts the player stacks over the
/// picture both land here, so there is one toast look in the app rather than
/// one per caller.
///
/// [opaque] is the reduced-transparency swap: an opaque surface of equivalent
/// contrast, never a dropped toast.
class AnalogToastSurface extends StatelessWidget {
  const AnalogToastSurface({
    super.key,
    required this.child,
    this.opaque = false,
    this.prominent = false,
    this.margin = const EdgeInsets.only(top: AnalogSpace.smPx),
  });

  final Widget child;
  final bool opaque;

  /// Sized to be caught out of the corner of your eye.
  ///
  /// The app-wide rail sets this; the player's chat stack does not. They are
  /// answering different questions. A chat toast sits over a film you are
  /// watching and must stay out of the way — it is a courtesy copy of
  /// something already in the drawer. A rail notice is the ONLY place its
  /// message appears, and a notice nobody notices is not a notice.
  final bool prominent;

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: LiquidGlass(
        opaque: opaque,
        borderRadius: BorderRadius.circular(
          prominent ? AnalogRadius.cardPx + 4 : AnalogRadius.cardPx,
        ),
        padding: prominent
            ? const EdgeInsets.symmetric(
                horizontal: AnalogSpace.lgPx,
                vertical: AnalogSpace.mdPx + 2,
              )
            : const EdgeInsets.symmetric(
                horizontal: AnalogSpace.mdPx,
                vertical: AnalogSpace.smPx + 2,
              ),
        shadow: [
          BoxShadow(
            color: AnalogColor.shadowCastStrong,
            blurRadius: prominent ? 44 : AnalogElevation.focusBlurPx,
            offset: Offset(0, prominent ? 16 : AnalogElevation.restOffsetYPx),
          ),
        ],
        child: child,
      ),
    );
  }
}

/// One live notice.
@immutable
class AnalogToast {
  const AnalogToast({
    required this.id,
    required this.message,
    required this.tone,
  });

  final int id;
  final String message;
  final AnalogToastTone tone;
}

/// The app-wide transient-notice rail.
///
/// Mounted once, above the router, so a notifier with nothing but the root
/// navigator's context can still raise a notice — which is exactly the party
/// socket's situation: its handlers run for the whole app lifetime and belong
/// to no screen.
///
/// The stack depth and the lifetime are [AnalogTiming.toastMaxStack] and
/// [AnalogTiming.toastLifetimeMs], the same two constants the player's chat
/// toasts run on. Notices are never interactive: they sit under an
/// [IgnorePointer] so they cannot swallow a click meant for the content behind
/// them, and they expire on their own clock rather than waiting to be
/// dismissed.
class AnalogToastHost extends StatefulWidget {
  const AnalogToastHost({super.key, required this.child, this.topInsetPx = 0});

  final Widget child;

  /// Clearance for a desktop window's caption strip.
  ///
  /// The rail is above the router — above dialogs, menus and the control panel
  /// — but the window chrome wraps the whole app and so paints above IT. Passed
  /// in rather than read here: this kit does not import the desktop shell, and
  /// a notice tucked under the caption buttons would be the one thing on screen
  /// the rail cannot outrank.
  final double topInsetPx;

  /// The nearest host, or null when none is mounted — a widget test that pumps
  /// a screen in isolation should not crash because it left the rail out.
  static AnalogToastHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AnalogToastHostState>();

  @override
  State<AnalogToastHost> createState() => AnalogToastHostState();
}

class AnalogToastHostState extends State<AnalogToastHost> {
  final List<AnalogToast> _live = [];
  final Map<int, Timer> _timers = {};

  /// Toasts playing their exit. They are still in [_live] — and still laid
  /// out — until the animation ends, which is the whole point: removing the
  /// row on the same frame the timer fires makes the ones below it jump.
  final Set<int> _leaving = {};

  int _nextId = 0;

  void show(String message, {AnalogToastTone tone = AnalogToastTone.info}) {
    final id = _nextId++;
    setState(() {
      _live.add(AnalogToast(id: id, message: message, tone: tone));
      // Count only the toasts that are not already on their way out, or a
      // stack sitting at its limit would re-expire the same leaving toast
      // forever — the list length does not drop until the exit finishes.
      while (_live.where((t) => !_leaving.contains(t.id)).length >
          AnalogTiming.toastMaxStack) {
        _expire(_live.firstWhere((t) => !_leaving.contains(t.id)).id);
      }
    });
    _timers[id] = Timer(AnalogTiming.toastLifetimeMs, () => _expire(id));
  }

  void _expire(int id) {
    if (_leaving.contains(id)) return;
    if (_live.indexWhere((t) => t.id == id) < 0) return;
    _timers.remove(id)?.cancel();
    _leaving.add(id);
    _timers[id] = Timer(_exitMs, () => _remove(id));
    // show() already holds a setState; a nested one is a no-op but harmless,
    // and calling it here is what makes a plain timer expiry repaint.
    if (mounted) setState(() {});
  }

  void _remove(int id) {
    _timers.remove(id)?.cancel();
    _leaving.remove(id);
    if (!mounted) {
      _live.removeWhere((t) => t.id == id);
      return;
    }
    setState(() => _live.removeWhere((t) => t.id == id));
  }

  /// The exit is deliberately quicker than the entry: arriving should be
  /// noticed, leaving should not.
  static const Duration _exitMs = AnalogMotion.chromeFadeMs;

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_live.isNotEmpty)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: AnalogSpace.lgPx + widget.topInsetPx,
                    right: AnalogSpace.lgPx,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final toast in _live)
                          _ToastRow(
                            key: ValueKey(toast.id),
                            toast: toast,
                            leaving: _leaving.contains(toast.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Raise a transient notice on the nearest [AnalogToastHost].
///
/// A no-op when no host is mounted, deliberately: a notice is never the only
/// path to information, and a missing rail must not take an app down.
void showAnalogToast(
  BuildContext context,
  String message, {
  AnalogToastTone tone = AnalogToastTone.info,
}) {
  AnalogToastHost.maybeOf(context)?.show(message, tone: tone);
}

/// One notice, with its arrival and departure.
///
/// The row enters by sliding in from the right edge it is anchored to, fading
/// up and unrolling to its height so the toasts already on screen slide down to
/// make room rather than being shoved. It leaves the same way, faster, and the
/// host keeps it mounted until that finishes.
class _ToastRow extends StatefulWidget {
  const _ToastRow({super.key, required this.toast, required this.leaving});

  final AnalogToast toast;
  final bool leaving;

  @override
  State<_ToastRow> createState() => _ToastRowState();
}

class _ToastRowState extends State<_ToastRow> {
  /// False for exactly one frame, so the implicit animations have a starting
  /// value to travel FROM. Built open on the first frame, they would simply
  /// appear.
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final open = _shown && !widget.leaving;
    final tone = widget.toast.tone;

    final surface = Semantics(
      liveRegion: true,
      label: widget.toast.message,
      excludeSemantics: true,
      child: AnalogToastSurface(
        opaque: media.highContrast,
        prominent: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The tone reads three ways — bar, glyph, and the glyph's tint —
            // so it survives a greyscale display and a colour-blind viewer.
            Container(
              width: 4,
              height: 34,
              margin: const EdgeInsets.only(right: AnalogSpace.mdPx),
              decoration: BoxDecoration(
                color: tone.edge,
                borderRadius: BorderRadius.circular(AnalogRadius.pillPx),
              ),
            ),
            // The glyph on its own tinted disc rather than loose in the row:
            // at this size a bare icon beside 16px text reads as punctuation.
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.ink.withValues(alpha: 0.16),
              ),
              child: Icon(tone.glyph, size: 19, color: tone.ink),
            ),
            const SizedBox(width: AnalogSpace.mdPx),
            Flexible(
              child: Text(
                widget.toast.message,
                style: const TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  color: AnalogColor.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // A viewer who asked for less motion gets the toast, not the entrance.
    if (media.disableAnimations) {
      return widget.leaving ? const SizedBox.shrink() : surface;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: open ? 1 : 0),
      duration: widget.leaving
          ? AnalogMotion.chromeFadeMs
          : AnalogMotion.fastStepMs,
      curve: AnalogMotion.chromeFadeEase,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.topRight,
          heightFactor: t,
          child: Opacity(
            opacity: t,
            // Arrives slightly under size and settles to full — the eye catches
            // a change of scale faster than a change of position. It grows INTO
            // place and stops: chrome does not overshoot, so there is no bounce
            // at the end of it (AnalogMotion.settleEase is the only curve
            // allowed to, and it belongs to things with mass).
            child: Transform.scale(
              scale: 0.94 + 0.06 * t,
              alignment: Alignment.centerRight,
              // A fraction of the child's own width — AnimatedSlide and
              // FractionalTranslation both measure in child sizes, not pixels.
              child: FractionalTranslation(
                translation: Offset(0.28 * (1 - t), 0),
                child: child,
              ),
            ),
          ),
        ),
      ),
      child: surface,
    );
  }
}
