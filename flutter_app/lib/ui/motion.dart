import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'tokens.dart';

/// Reusable motion helpers (PLAN PKG-0 §Motion). Dependency-light: built on
/// Flutter's own implicit/explicit animations + go_router's transition page, so
/// screens get consistent, calm motion without pulling in an animation package.

/// A ~180ms fade-through [CustomTransitionPage] for top-level push routes
/// (`/detail/:id`, `/party/:id`). Shelled tab routes deliberately stay on
/// `NoTransitionPage` (instant swap is an anti-flicker fix) — do not use this
/// for them.
CustomTransitionPage<T> fadeThroughPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: AppMotion.page,
    reverseTransitionDuration: AppMotion.page,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.standard,
      );
      return FadeTransition(
        opacity: curved,
        child: FadeTransition(
          // Fade the outgoing route out as the new one pushes in.
          opacity: Tween<double>(begin: 1, end: 1).animate(secondaryAnimation),
          child: child,
        ),
      );
    },
  );
}

/// Fades a child in with a small (default 8px) upward slide the first time it
/// mounts. Give each item in a list/grid an increasing [delay] (see
/// [StaggeredList]) for a cascading entrance. Purely decorative — it never
/// gates layout or interaction.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 8,
    this.duration = AppMotion.reveal,
    this.curve = AppMotion.emphasized,
  });

  final Widget child;
  final Duration delay;

  /// Vertical slide distance in logical pixels (positive = slides up into place).
  final double offset;
  final Duration duration;
  final Curve curve;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    // The delay is folded into the controller via an [Interval] rather than a
    // `Future.delayed` Timer, so a `Reveal` never leaves a pending timer for
    // the test binding to trip over.
    _c = AnimationController(
      vsync: this,
      duration: widget.delay + widget.duration,
    );
    final total = (widget.delay + widget.duration).inMicroseconds;
    final start = total == 0 ? 0.0 : widget.delay.inMicroseconds / total;
    _anim = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: widget.curve),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Opacity(
          opacity: _anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _anim.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Wraps a list of [children] so each one [Reveal]s in, index-delayed, for a
/// staggered entrance on rails/grids/rows/chat/tiles. This is a plain grouping
/// helper — lay the returned children out in any Column/Row/Wrap/Grid.
class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.direction = Axis.vertical,
    this.spacing = 0,
    this.step = AppMotion.stagger,
    this.maxStagger = 10,
    this.offset = 8,
  });

  final List<Widget> children;
  final Axis direction;

  /// Gap inserted between children (via the enclosing Flex).
  final double spacing;

  /// Per-index delay increment.
  final Duration step;

  /// Cap the stagger so long lists don't animate forever.
  final int maxStagger;
  final double offset;

  List<Widget> _revealed() {
    return [
      for (var i = 0; i < children.length; i++)
        Reveal(
          key: children[i].key == null ? null : ValueKey(children[i].key),
          delay: step * (i > maxStagger ? maxStagger : i),
          offset: offset,
          child: children[i],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: direction,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: _revealed(),
    );
  }
}
