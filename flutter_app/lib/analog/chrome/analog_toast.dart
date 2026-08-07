import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';

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
    this.margin = const EdgeInsets.only(top: AnalogSpace.smPx),
  });

  final Widget child;
  final bool opaque;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(
        horizontal: AnalogSpace.mdPx,
        vertical: AnalogSpace.smPx,
      ),
      decoration: BoxDecoration(
        color: opaque ? AnalogColor.stageSurface2 : AnalogColor.backdropScrim,
        borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
        border: Border.all(color: AnalogColor.line),
      ),
      child: child,
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
  const AnalogToastHost({super.key, required this.child});

  final Widget child;

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
  int _nextId = 0;

  void show(String message, {AnalogToastTone tone = AnalogToastTone.info}) {
    final id = _nextId++;
    setState(() {
      _live.add(AnalogToast(id: id, message: message, tone: tone));
      while (_live.length > AnalogTiming.toastMaxStack) {
        _expire(_live.first.id, rebuild: false);
      }
    });
    _timers[id] = Timer(AnalogTiming.toastLifetimeMs, () => _expire(id));
  }

  void _expire(int id, {bool rebuild = true}) {
    _timers.remove(id)?.cancel();
    final removed = _live.indexWhere((t) => t.id == id) >= 0;
    if (!removed) return;
    if (rebuild) {
      if (!mounted) return;
      setState(() => _live.removeWhere((t) => t.id == id));
    } else {
      _live.removeWhere((t) => t.id == id);
    }
  }

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
            left: 0,
            right: 0,
            child: SafeArea(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(top: AnalogSpace.lgPx),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final toast in _live)
                        _ToastRow(key: ValueKey(toast.id), toast: toast),
                    ],
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

class _ToastRow extends StatelessWidget {
  const _ToastRow({super.key, required this.toast});

  final AnalogToast toast;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Semantics(
      liveRegion: true,
      label: toast.message,
      excludeSemantics: true,
      child: AnalogToastSurface(
        opaque: media.highContrast,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(toast.tone.glyph, size: 15, color: toast.tone.ink),
            const SizedBox(width: AnalogSpace.smPx),
            Flexible(
              child: Text(
                toast.message,
                style: const TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  color: AnalogColor.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
