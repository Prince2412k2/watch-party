import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/analog_tokens.dart';

/// One row of an [AnalogContextMenu].
@immutable
class AnalogMenuAction {
  const AnalogMenuAction({
    required this.label,
    required this.onSelected,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;

  /// Destructive. Carries the reserved red and a heavier label weight, so the
  /// row is still marked when the colour is not perceivable.
  final bool danger;
}

/// A secondary-action menu on an existing row.
///
/// Presented through Material's [showMenu] on purpose: the menu route already
/// gets focus traversal, arrow-key movement, Escape, and correct placement
/// against the screen edges, and none of that was ever the thing that looked
/// wrong. Only the surface is this kit's.
///
/// The reference forbids important actions behind gesture-only interaction, so
/// the menu opens four ways — secondary tap, long press, the Context Menu key,
/// and Shift+F10 — and the enclosing [Focus] deliberately does not take focus
/// itself, so the keys arrive from whichever control inside the row the user is
/// actually on.
///
/// This is a convenience surface, never the only path: every action it offers
/// must also exist as a visible control in the row it wraps.
class AnalogContextMenu extends StatefulWidget {
  const AnalogContextMenu({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<AnalogMenuAction> actions;
  final Widget child;

  @override
  State<AnalogContextMenu> createState() => _AnalogContextMenuState();
}

class _AnalogContextMenuState extends State<AnalogContextMenu> {
  Future<void> _open(Offset globalPosition) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) return;

    final selected = await showMenu<AnalogMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: AnalogColor.stageSurface,
      surfaceTintColor: const Color(0x00000000),
      shadowColor: AnalogColor.shadowCastStrong,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AnalogRadius.sheetPx),
        side: const BorderSide(color: AnalogColor.lineStrong),
      ),
      items: [
        for (final action in widget.actions)
          PopupMenuItem<AnalogMenuAction>(
            value: action,
            height: 38,
            padding: const EdgeInsets.symmetric(
              horizontal: AnalogSpace.mdPx,
              vertical: AnalogSpace.xsPx,
            ),
            child: Row(
              children: [
                if (action.icon != null) ...[
                  Icon(
                    action.icon,
                    size: 16,
                    color: action.danger
                        ? AnalogColor.statusDanger
                        : AnalogColor.inkDim,
                  ),
                  const SizedBox(width: AnalogSpace.smPx),
                ],
                Text(
                  action.label,
                  style: TextStyle(
                    fontFamily: AnalogType.sansFamily,
                    fontSize: 13,
                    fontWeight: action.danger
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: action.danger
                        ? AnalogColor.statusDanger
                        : AnalogColor.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    selected?.onSelected();
  }

  void _openAtSelf() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _open(box.localToGlobal(box.size.centerLeft(Offset.zero)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isMenuKey = event.logicalKey == LogicalKeyboardKey.contextMenu;
    final isShiftF10 =
        event.logicalKey == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
    if (!isMenuKey && !isShiftF10) return KeyEventResult.ignored;
    _openAtSelf();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapDown: (details) => _open(details.globalPosition),
        onLongPressStart: (details) => _open(details.globalPosition),
        child: widget.child,
      ),
    );
  }
}
