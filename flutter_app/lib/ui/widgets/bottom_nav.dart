import 'package:flutter/material.dart';

import '../palette.dart';
import '../tokens.dart';
import 'nav_rail.dart' show NavDestination;

/// The bottom-centered floating primary navigation (`.web-bottom-nav`,
/// styles.css:333-369). Replaces the old left [NavRail]: a transparent,
/// centered row of icon+label tabs with NO panel behind them. The dim label
/// brightens on hover and, when active, sits at full text weight over an
/// animated red underline bar (`scaleX 0→1`, brand red).
///
/// Layout/positioning (the `left:20% right:20% bottom:10` band) is owned by the
/// shell; this widget only paints the tab row.
class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.destinations,
    required this.currentRoute,
    required this.onSelect,
  });

  final List<NavDestination> destinations;
  final String currentRoute;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // gap: clamp(18px, 3.6vw, 58px).
    final gap = (MediaQuery.of(context).size.width * 0.036).clamp(18.0, 58.0);
    final children = <Widget>[];
    for (var i = 0; i < destinations.length; i++) {
      if (i > 0) children.add(SizedBox(width: gap));
      final d = destinations[i];
      children.add(
        _NavTab(
          dest: d,
          active: currentRoute == d.route,
          onTap: () => onSelect(d.route),
        ),
      );
    }
    return SizedBox(
      height: 62,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({
    required this.dest,
    required this.active,
    required this.onTap,
  });

  final NavDestination dest;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final active = widget.active;
    final color = active || _hover ? wp.text : wp.dim;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88),
          child: SizedBox(
            height: 62,
            child: Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.dest.icon, size: 18, color: color),
                      const SizedBox(width: 8),
                      AnimatedDefaultTextStyle(
                        duration: AppMotion.hover,
                        style: TextStyle(
                          fontFamily: AppFonts.sans,
                          fontSize: 14,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                        child: Text(widget.dest.label),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 0,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(end: active ? 1.0 : 0.0),
                        duration: AppMotion.hover,
                        curve: AppMotion.standard,
                        builder: (context, factor, child) => Center(
                          child: SizedBox(
                            width: constraints.maxWidth * factor,
                            child: child,
                          ),
                        ),
                        child: Container(
                          height: 3,
                          decoration: const BoxDecoration(
                            color: kBrandRed,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
