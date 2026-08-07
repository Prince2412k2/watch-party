import 'package:flutter/material.dart';

import '../../analog/chrome/analog_badge.dart';
import '../../analog/chrome/analog_pressable.dart';
import '../../analog/chrome/analog_tooltip.dart';
import '../analog_tokens.dart';

/// A single navigation destination for [NavRail].
class NavDestination {
  const NavDestination({
    required this.icon,
    required this.label,
    required this.route,
    this.badge = 0,
  });
  final IconData icon;
  final String label;
  final String route;
  final int badge;
}

/// FROZEN CONTRACT (PLAN §3.6). The app shell's left navigation. Signature is
/// frozen.
///
/// Rows are [AnalogPressable]s now, which is not only a repaint: the old rows
/// were a `GestureDetector` inside a `MouseRegion` and could not be reached
/// from the keyboard or a remote at all. The active row is marked by a detent
/// hairline down its leading edge and a heavier label as well as its plate, so
/// "you are here" survives greyscale.
///
/// [compact] collapses to an icon-only rail (labels become tooltips) for
/// narrow windows — additive, default `false` keeps the original contract.
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.destinations,
    required this.currentRoute,
    required this.onSelect,
    this.width = 240,
    this.compact = false,
  });

  final List<NavDestination> destinations;
  final String currentRoute;
  final ValueChanged<String> onSelect;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 72 : width,
      color: AnalogColor.stageGround,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AnalogSpace.smPx : AnalogSpace.lgPx,
        vertical: AnalogSpace.xlPx,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: compact ? 0 : AnalogSpace.smPx,
              bottom: AnalogSpace.xlPx,
            ),
            child: compact
                ? const Icon(
                    Icons.theaters_outlined,
                    color: AnalogColor.ink,
                    size: 20,
                  )
                : const Text(
                    'Watchparty',
                    style: TextStyle(
                      fontFamily: AnalogType.sansFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AnalogColor.ink,
                    ),
                  ),
          ),
          for (final d in destinations)
            _NavRow(
              dest: d,
              active: currentRoute == d.route,
              compact: compact,
              onTap: () => onSelect(d.route),
            ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.dest,
    required this.active,
    required this.onTap,
    this.compact = false,
  });
  final NavDestination dest;
  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final row = AnalogPressable(
      onPressed: onTap,
      semanticLabel: dest.label,
      selected: active,
      excludeSemantics: true,
      builder: (context, state) {
        final lit = active || state.lit;
        final color = lit ? AnalogColor.ink : AnalogColor.inkDim;
        return AnalogFocusRing(
          visible: state.focused,
          inset: 2,
          child: AnimatedContainer(
            duration: AnalogMotion.chromeFadeMs,
            curve: AnalogMotion.chromeFadeEase,
            padding: EdgeInsets.only(
              left: compact ? 0 : AnalogSpace.mdPx,
              right: compact ? 0 : AnalogSpace.mdPx,
              top: 10,
              bottom: 10,
            ),
            margin: const EdgeInsets.only(bottom: AnalogSpace.xsPx),
            decoration: BoxDecoration(
              color: active
                  ? AnalogColor.stageSurface2
                  : (state.lit
                        ? AnalogColor.stageSurface
                        : const Color(0x00000000)),
              borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
              // The detent down the leading edge is what marks the current
              // destination without a colour: it is either there or it is not.
              border: Border(
                left: BorderSide(
                  width: AnalogHairline.idlePx,
                  color: active ? AnalogColor.ink : const Color(0x00000000),
                ),
              ),
            ),
            child: compact
                ? SizedBox(
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(dest.icon, size: 20, color: color),
                        if (dest.badge > 0)
                          const Positioned(
                            top: 4,
                            right: 12,
                            child: SizedBox(
                              width: 6,
                              height: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AnalogColor.statusSuccess,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Icon(dest.icon, size: 19, color: color),
                      const SizedBox(width: AnalogSpace.mdPx),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: AnalogMotion.chromeFadeMs,
                          curve: AnalogMotion.chromeFadeEase,
                          style: TextStyle(
                            fontFamily: AnalogType.sansFamily,
                            color: color,
                            fontSize: 14.5,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          child: Text(dest.label),
                        ),
                      ),
                      if (dest.badge > 0)
                        AnalogBadge(
                          child: Text(
                            '${dest.badge}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: AnalogType.monoFamily,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );

    return compact ? AnalogTooltip(message: dest.label, child: row) : row;
  }
}
