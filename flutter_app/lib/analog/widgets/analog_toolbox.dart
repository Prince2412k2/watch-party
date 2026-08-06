import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/analog_tokens.dart';

/// Which stage corner a toolbox is pinned to.
///
/// "Profile is a compact control in the upper-right corner… Watch Party is a
/// compact control in the lower-right corner." (analog-interface-reference.md
/// §Primary navigation.)
enum AnalogToolboxCorner {
  upperRight,
  lowerRight;

  /// The panel opens away from the edge the trigger is pinned to, so an
  /// expanded toolbox never grows off-stage.
  bool get panelBelowTrigger => this == AnalogToolboxCorner.upperRight;
}

/// A compact corner control that expands an inline toolbox.
///
/// The reference is explicit that this is *not* a dashboard and *not* a
/// sidebar: "Activating it expands an inline toolbox rather than opening a
/// separate dashboard or permanent sidebar", and "The expanded surface must not
/// cover primary content or compete with the bottom navigation." So the panel
/// is corner-anchored, width-capped, and height-capped by
/// [maxPanelHeight] — it is a drawer in the corner, never a modal over the
/// stage.
///
/// This is chrome, not artwork, so [AnalogRadius.sheetPx] is legitimate here —
/// and only here. Nothing in this file may be reused for a poster.
///
/// Open state is uncontrolled unless [open] is supplied.
class AnalogToolbox extends StatefulWidget {
  const AnalogToolbox({
    super.key,
    required this.corner,
    required this.label,
    required this.child,
    this.icon,
    this.trigger,
    this.open,
    this.onOpenChanged,
    this.badgeCount = 0,
    this.live = false,
    this.maxPanelWidth = 320,
    this.maxPanelHeight = 420,
  }) : assert(
         icon != null || trigger != null,
         'a toolbox trigger needs a glyph: pass icon or trigger',
       );

  final AnalogToolboxCorner corner;

  /// Accessible name for the compact control, e.g. `Profile`.
  final String label;

  /// The toolbox contents. Only built while the toolbox is open, so a closed
  /// toolbox costs nothing and cannot be found by a test that expects it shut.
  final Widget child;

  final IconData? icon;

  /// Replaces the default glyph inside the compact control.
  final Widget? trigger;

  /// Supply to drive open state from outside; omit to let the toolbox own it.
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;

  /// Count badge on the trigger — guests waiting for approval, and the like.
  final int badgeCount;

  /// Marks a live session with a status dot rather than colour alone.
  final bool live;

  final double maxPanelWidth;
  final double maxPanelHeight;

  @override
  State<AnalogToolbox> createState() => _AnalogToolboxState();
}

class _AnalogToolboxState extends State<AnalogToolbox>
    with SingleTickerProviderStateMixin {
  final _panelFocus = FocusScopeNode(debugLabel: 'AnalogToolbox');
  late bool _open = widget.open ?? false;

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AnalogMotion.drawerMs,
    value: _open ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _reveal,
    curve: AnalogMotion.drawerEase,
    reverseCurve: AnalogMotion.drawerEase,
  );

  bool get _isOpen => widget.open ?? _open;

  @override
  void initState() {
    super.initState();
    _reveal.addStatusListener(_onRevealStatus);
  }

  @override
  void didUpdateWidget(AnalogToolbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != null && widget.open != oldWidget.open) {
      _open = widget.open!;
      _drive(_open);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _reveal.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  /// Opening a toolbox takes focus so the keyboard and a remote can both walk
  /// its contents; closing hands focus back to the enclosing scope, which is
  /// the shelf the user came from.
  ///
  /// Focus is claimed on `completed` rather than immediately: the panel is not
  /// in the tree until the reveal has ticked, and requesting focus on an
  /// unattached scope node silently does nothing.
  void _onRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _isOpen) {
      _panelFocus.requestFocus();
    }
  }

  void _drive(bool open) {
    if (open) {
      _reveal.forward();
    } else {
      _reveal.reverse();
      if (_panelFocus.hasFocus) _panelFocus.unfocus();
    }
  }

  void _setOpen(bool next) {
    if (next == _isOpen) return;
    if (widget.open == null) setState(() => _open = next);
    widget.onOpenChanged?.call(next);
    if (widget.open == null) _drive(next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _isOpen) {
      _setOpen(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Hand-rolled rather than AnimatedSwitcher + SizeTransition: that pair
    // shrink-wraps only the axis it animates, so the panel slot silently grew
    // to the full stage width and the closed toolbox stopped being compact.
    // Here the width shrink-wraps in both states and a fully closed toolbox
    // builds no panel at all.
    final panel = AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value.clamp(0.0, 1.0);
        if (t == 0) return const SizedBox.shrink();
        return Opacity(
          opacity: t,
          child: ClipRect(
            child: Align(
              // The panel unrolls away from the edge its trigger is pinned to.
              alignment: widget.corner.panelBelowTrigger
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              widthFactor: 1,
              heightFactor: t,
              child: Padding(
                padding: widget.corner.panelBelowTrigger
                    ? const EdgeInsets.only(top: AnalogSpace.mdPx)
                    : const EdgeInsets.only(bottom: AnalogSpace.mdPx),
                child: _ToolboxPanel(
                  maxWidth: widget.maxPanelWidth,
                  maxHeight: widget.maxPanelHeight,
                  focusScope: _panelFocus,
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );

    final trigger = _ToolboxTrigger(
      label: widget.label,
      icon: widget.icon,
      open: _isOpen,
      live: widget.live,
      badgeCount: widget.badgeCount,
      onTap: () => _setOpen(!_isOpen),
      child: widget.trigger,
    );

    return TapRegion(
      onTapOutside: (_) => _setOpen(false),
      child: Focus(
        onKeyEvent: _onKey,
        skipTraversal: true,
        canRequestFocus: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: widget.corner.panelBelowTrigger
              ? [trigger, panel]
              : [panel, trigger],
        ),
      ),
    );
  }
}

class _ToolboxPanel extends StatelessWidget {
  const _ToolboxPanel({
    required this.maxWidth,
    required this.maxHeight,
    required this.focusScope,
    required this.child,
  });

  final double maxWidth;
  final double maxHeight;
  final FocusScopeNode focusScope;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: focusScope,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AnalogColor.stageSurface,
            // Chrome radius — legitimate on a sheet, never on artwork.
            borderRadius: BorderRadius.circular(AnalogRadius.sheetPx),
            border: Border.all(color: AnalogColor.line),
            boxShadow: const [
              BoxShadow(
                color: AnalogColor.shadowCastStrong,
                blurRadius: AnalogElevation.focusBlurPx,
                offset: Offset(
                  AnalogElevation.focusOffsetXPx,
                  AnalogElevation.focusOffsetYPx,
                ),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AnalogSpace.lgPx),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
}

class _ToolboxTrigger extends StatefulWidget {
  const _ToolboxTrigger({
    required this.label,
    required this.icon,
    required this.open,
    required this.live,
    required this.badgeCount,
    required this.onTap,
    required this.child,
  });

  final String label;
  final IconData? icon;
  final bool open;
  final bool live;
  final int badgeCount;
  final VoidCallback onTap;
  final Widget? child;

  @override
  State<_ToolboxTrigger> createState() => _ToolboxTriggerState();
}

class _ToolboxTriggerState extends State<_ToolboxTrigger> {
  bool _hover = false;
  bool _focused = false;

  static const double _size = 44;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.select:
        widget.onTap();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.open || _hover || _focused;
    return Semantics(
      button: true,
      expanded: widget.open,
      label: widget.label,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (has) => setState(() => _focused = has),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: AnalogMotion.chromeFadeMs,
                  curve: AnalogMotion.chromeFadeEase,
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: lit
                        ? AnalogColor.stageSurface2
                        : AnalogColor.stageSurface,
                    borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
                    border: Border.all(
                      color: lit ? AnalogColor.lineStrong : AnalogColor.line,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: AnalogColor.shadowCast,
                        blurRadius: AnalogElevation.restBlurPx,
                        offset: Offset(
                          AnalogElevation.restOffsetXPx,
                          AnalogElevation.restOffsetYPx,
                        ),
                      ),
                    ],
                  ),
                  child: Center(
                    child:
                        widget.child ??
                        Icon(
                          widget.icon,
                          size: 20,
                          color: lit ? AnalogColor.ink : AnalogColor.inkDim,
                        ),
                  ),
                ),
                if (widget.live)
                  const Positioned(
                    right: -2,
                    bottom: -2,
                    child: _StatusDot(color: AnalogColor.statusPartyLive),
                  ),
                if (widget.badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: _Badge(count: widget.badgeCount),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: AnalogColor.stageGround, width: 2),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: AnalogSpace.xsPx),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AnalogColor.statusDanger,
      borderRadius: BorderRadius.circular(AnalogRadius.pillPx),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        fontFamily: AnalogType.sansFamily,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AnalogColor.onAccent,
      ),
    ),
  );
}
