import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';

/// One primary mode along the bottom edge of the stage.
class AnalogNavMode {
  const AnalogNavMode({required this.id, required this.label, this.icon});

  /// Stable identity — the route in this app, but the widget never assumes so.
  final String id;
  final String label;
  final IconData? icon;
}

/// The bottom-edge mode strip.
///
/// "The main modes remain visible along the bottom edge" and "No permanent
/// sidebar" (analog-interface-reference.md §Primary navigation). This is not a
/// panel: it is a row of labels over the stage, with the current mode marked by
/// a mechanical hairline detent rather than a coloured pill or a brand-red
/// underline.
///
/// The detent uses [AnalogHairline.idlePx] / [AnalogHairline.activePx] and
/// snaps on [AnalogMotion.detentMs] — short travel, clear detent, no bounce.
/// Selection never relies on colour alone: the active label also carries weight.
class AnalogNav extends StatelessWidget {
  const AnalogNav({
    super.key,
    required this.modes,
    required this.currentId,
    required this.onSelect,
  });

  final List<AnalogNavMode> modes;
  final String currentId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Modes',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final mode in modes)
            _AnalogNavTab(
              key: ValueKey('analog-nav-${mode.id}'),
              mode: mode,
              active: mode.id == currentId,
              onSelect: () => onSelect(mode.id),
            ),
        ],
      ),
    );
  }
}

class _AnalogNavTab extends StatefulWidget {
  const _AnalogNavTab({
    super.key,
    required this.mode,
    required this.active,
    required this.onSelect,
  });

  final AnalogNavMode mode;
  final bool active;
  final VoidCallback onSelect;

  @override
  State<_AnalogNavTab> createState() => _AnalogNavTabState();
}

class _AnalogNavTabState extends State<_AnalogNavTab> {
  bool _hover = false;
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.select:
        widget.onSelect();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.active || _hover || _focused;
    final color = lit ? AnalogColor.ink : AnalogColor.inkDim;
    final icon = widget.mode.icon;

    return Semantics(
      selected: widget.active,
      button: true,
      label: widget.mode.label,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (has) => setState(() => _focused = has),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            child: ConstrainedBox(
              // Comfortably past the AnalogHairline.hitPx touch floor, which
              // the detent line itself is nowhere near.
              constraints: const BoxConstraints(minWidth: 92, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AnalogSpace.lgPx,
                  vertical: AnalogSpace.mdPx,
                ),
                // A Stack, not a Column: the detent has no intrinsic width of
                // its own, so it has to inherit the label's — and a Column in
                // the nav's unbounded cross axis gives it nothing to stretch
                // against.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: AnalogSpace.mdPx,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 16, color: color),
                            const SizedBox(width: AnalogSpace.smPx),
                          ],
                          AnimatedDefaultTextStyle(
                            duration: AnalogMotion.chromeFadeMs,
                            curve: AnalogMotion.chromeFadeEase,
                            style: TextStyle(
                              fontFamily: AnalogType.sansFamily,
                              fontSize: 13,
                              letterSpacing: 0.6,
                              fontWeight: widget.active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: color,
                            ),
                            child: Text(widget.mode.label),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _Detent(active: widget.active, lit: lit),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mechanical detent under a mode: a hairline that thickens and runs the
/// full label width when the mode is current.
class _Detent extends StatelessWidget {
  const _Detent({required this.active, required this.lit});

  final bool active;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1 : 0),
      duration: AnalogMotion.detentMs,
      curve: AnalogMotion.detentEase,
      builder: (context, t, _) => SizedBox(
        height: AnalogHairline.activePx,
        child: FractionallySizedBox(
          alignment: Alignment.center,
          widthFactor: 0.25 + 0.75 * t,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height:
                  AnalogHairline.idlePx +
                  (AnalogHairline.activePx - AnalogHairline.idlePx) * t,
              color: Color.lerp(
                lit ? AnalogColor.line : const Color(0x00000000),
                AnalogColor.ink,
                t,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
