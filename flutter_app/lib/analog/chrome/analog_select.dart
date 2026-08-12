import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';

/// The top edge of [key]'s box in [overlay]'s space, or null when it is not
/// mounted — a caller that passes an anchor the layout has since dropped gets
/// the default placement rather than an exception.
double? _topOf(GlobalKey? key, RenderBox overlay) {
  final box = key?.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero, ancestor: overlay).dy;
}

/// One choice in an [showAnalogSelect] list.
@immutable
class AnalogChoice<T> {
  const AnalogChoice({
    required this.value,
    required this.label,
    this.detail,
    this.icon,
    this.onDelete,
  });

  final T value;

  /// The whole row. Keep it to the thing that distinguishes this choice from
  /// its siblings — codecs and channel counts belong in [detail], if anywhere.
  final String label;

  /// Secondary text, shown small and dim after the label. Optional by design:
  /// most choices do not need one, and a list where every row has two lines is
  /// a list nobody reads.
  final String? detail;

  final IconData? icon;

  /// A destructive action on this row, shown as a trailing glyph.
  final VoidCallback? onDelete;
}

/// A group of choices, marked by an ICON rather than a word.
///
/// The panel this replaced printed "AUDIO" and "SUBTITLES" as letter-spaced
/// mono headings — two lines of chrome to say what a speaker glyph and a
/// caption glyph say instantly, in a menu whose rows are one line each. The
/// icon sits in the gutter beside the group so the eye can find its section
/// without reading anything.
@immutable
class AnalogChoiceGroup<T> {
  const AnalogChoiceGroup({required this.icon, required this.choices});

  final IconData icon;
  final List<AnalogChoice<T>> choices;
}

/// The kit's dropdown.
///
/// Opens as an **overlay anchored to [anchor]**, which is the whole reason it
/// exists. The track picker it replaced was an inline child of the copy
/// column: it pushed the layout around when it opened, inherited that column's
/// clip, and got cut off at the bottom with no way to reach the rest — the
/// "weird scrolling" was the page trying to scroll a panel that was never
/// meant to be page content.
///
/// Built on [showMenu] rather than a hand-rolled [OverlayPortal] because the
/// menu route already gets focus traversal, arrow keys, Escape, tap-outside
/// dismissal and screen-edge placement, and none of those were ever what
/// looked wrong. Only the surface is this kit's.
///
/// Minimal on purpose: no title bar, no close button (Escape and outside-tap
/// both work and neither costs a row), no word headings. What is left is the
/// choices and a tick against the current one.
Future<void> showAnalogSelect<T>({
  required BuildContext context,

  required GlobalKey anchor,
  required List<AnalogChoiceGroup<T>> groups,
  required T? selected,
  required ValueChanged<T> onSelected,

  /// An optional action pinned under the list — "add one of these". Drawn as
  /// its own labelled row; [footerTooltip] is the label.
  IconData? footerIcon,
  String? footerTooltip,
  VoidCallback? onFooter,

  /// Something the menu must not cover — the player's timeline. When given,
  /// the menu's BOTTOM edge is placed just above this widget's top edge
  /// instead of hanging off [anchor], so a control sitting under the scrubber
  /// still opens clear of it.
  GlobalKey? liftAbove,
  double width = 260,
}) async {
  final box = anchor.currentContext?.findRenderObject();
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (box is! RenderBox || overlay is! RenderBox || !box.hasSize) return;

  // Positioned relative to the OVERLAY, not the screen: the two differ
  // whenever the app sits inside a transformed or inset ancestor, and a menu
  // that is right on a bare window and wrong inside one is the hardest kind of
  // placement bug to notice.
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorRect = topLeft & box.size;

  // Right-aligned to the control, so a menu opened from the lower-right
  // cluster does not sprawl across the middle of the picture.
  final left = (anchorRect.right - width)
      .clamp(
        AnalogSpace.smPx,
        math.max(
          AnalogSpace.smPx,
          overlay.size.width - width - AnalogSpace.smPx,
        ),
      )
      .toDouble();

  // Every row is the same fixed height, so the menu's height is known before
  // it is built — which is what makes placing its BOTTOM edge possible at all.
  final rows =
      groups.fold<int>(0, (n, g) => n + g.choices.length) +
      (onFooter != null ? 1 : 0);
  final height = rows * _rowHeight + _menuPad * 2;

  final ceiling = _topOf(liftAbove, overlay);
  final top = ceiling == null
      ? anchorRect.bottom + AnalogSpace.smPx
      : math.max(AnalogSpace.smPx, ceiling - AnalogSpace.smPx - height);

  final chosen = await showMenu<AnalogChoice<T>>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(left, top, width, 0),
      Offset.zero & overlay.size,
    ),
    constraints: BoxConstraints(minWidth: width, maxWidth: width),
    color: AnalogColor.stageSurface,
    surfaceTintColor: const Color(0x00000000),
    shadowColor: AnalogColor.shadowCastStrong,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radius),
      side: const BorderSide(color: AnalogColor.line),
    ),
    items: [
      for (final group in groups)
        for (final choice in group.choices)
          PopupMenuItem<AnalogChoice<T>>(
            value: choice,
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: _rowPad),
            child: _ChoiceRow<T>(
              // Every row carries a glyph. Marking only the first of a group
              // left the rest sitting in an empty gutter, which read as
              // ragged rather than as a section.
              icon: choice.icon ?? group.icon,
              label: choice.label,
              detail: choice.detail,
              selected: choice.value == selected,
              onDelete: choice.onDelete,
            ),
          ),
      // No divider above this. The rule was the loudest thing in the menu,
      // and the row already reads as a different kind of thing: it is the
      // only one that never carries a tick.
      if (onFooter != null)
        PopupMenuItem<AnalogChoice<T>>(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: _rowPad),
          onTap: onFooter,
          child: _ChoiceRow<T>(
            icon: footerIcon ?? Icons.add,
            label: footerTooltip ?? 'Add',
            detail: null,
            selected: false,
            onDelete: null,
          ),
        ),
    ],
  );
  if (chosen != null) onSelected(chosen.value);
}

/// Row geometry, shared by the choices and the footer so they cannot drift.
const double _radius = 16;
const double _rowHeight = 42;
const double _rowPad = 14;

/// The most a trailing value may take before it starts truncating.
const double _detailWidth = 124;

/// [PopupMenuButton]'s own list padding, which the height maths has to match.
const double _menuPad = 8;

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onDelete,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? AnalogColor.ink : AnalogColor.inkDim;
    return Row(
      children: [
        Icon(icon, size: 17, color: ink),
        const SizedBox(width: AnalogSpace.mdPx - 2),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AnalogType.sansFamily,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: ink,
            ),
          ),
        ),
        // The value sits at the right, quieter than the label. It used to be
        // uppercase mono, which read as a machine code rather than as a
        // description of the row it belonged to.
        if (detail != null)
          // Capped, so a long value truncates instead of eating the label. The
          // label is what you are looking for; the value is what you check
          // once you have found it.
          Container(
            constraints: const BoxConstraints(maxWidth: _detailWidth),
            padding: const EdgeInsets.only(left: AnalogSpace.smPx),
            child: Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AnalogType.sansFamily,
                fontSize: 13,
                color: AnalogColor.inkFaint,
              ),
            ),
          ),
        if (onDelete != null)
          // Deepest recognizer wins the tap, so this takes the hit rather than
          // the PopupMenuItem's own InkWell underneath it. Pops first: calling
          // onDelete with the menu still open would leave a route showing a
          // row that no longer exists.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.of(context).pop();
              onDelete!();
            },
            child: const Padding(
              padding: EdgeInsets.only(left: AnalogSpace.smPx),
              child: Icon(
                Icons.close,
                size: 14,
                color: AnalogColor.statusDanger,
              ),
            ),
          ),
        // The tick is the only state marker, and it is a shape rather than a
        // colour — the reference forbids selection that relies on colour
        // alone, and a menu is exactly where that rule earns its keep.
        //
        // Its slot is always reserved, even when nothing is in it: appending
        // the tick only to the selected row shunted that row's value left, so
        // the column of values stopped lining up the moment you picked one.
        const SizedBox(width: AnalogSpace.smPx),
        SizedBox(
          width: 16,
          child: selected
              ? const Icon(Icons.check, size: 16, color: AnalogColor.ink)
              : null,
        ),
      ],
    );
  }
}
