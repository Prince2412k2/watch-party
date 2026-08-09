import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';
import 'analog_button.dart';

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

  /// The context the MENU ROUTE is pushed on, when it differs from the one the
  /// anchor lives in.
  ///
  /// `showMenu` needs a Navigator above its context. Chrome mounted in
  /// `MaterialApp.builder` — the player's transport bar, and anything else
  /// living above the router — has an Overlay but no Navigator, so opening any
  /// menu from there threw and the control looked simply dead. The caller can
  /// hand in a context that does have one.
  ///
  /// Position is unaffected: it is computed from [anchor]'s global rect, not
  /// from this.
  BuildContext? routeContext,
  required GlobalKey anchor,
  required List<AnalogChoiceGroup<T>> groups,
  required T? selected,
  required ValueChanged<T> onSelected,

  /// An optional action pinned under the list — "add one of these". Icon-only;
  /// its tooltip is its name.
  IconData? footerIcon,
  String? footerTooltip,
  VoidCallback? onFooter,
  double width = 300,
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

  final chosen = await showMenu<AnalogChoice<T>>(
    context: routeContext ?? context,
    // Hangs off the control that opened it, growing downwards, and flips
    // itself when there is no room below.
    position: RelativeRect.fromRect(
      Rect.fromLTWH(
        anchorRect.left,
        anchorRect.bottom + AnalogSpace.smPx,
        anchorRect.width,
        0,
      ),
      Offset.zero & overlay.size,
    ),
    constraints: BoxConstraints(minWidth: width, maxWidth: width),
    color: AnalogColor.stageSurface,
    surfaceTintColor: const Color(0x00000000),
    shadowColor: AnalogColor.shadowCastStrong,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AnalogRadius.cardPx),
      side: const BorderSide(color: AnalogColor.line),
    ),
    items: [
      for (var g = 0; g < groups.length; g++) ...[
        if (g > 0)
          const PopupMenuDivider(height: 1) as PopupMenuEntry<AnalogChoice<T>>,
        for (final choice in groups[g].choices)
          PopupMenuItem<AnalogChoice<T>>(
            value: choice,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: AnalogSpace.mdPx),
            child: _ChoiceRow<T>(
              choice: choice,
              // The group's icon rides the FIRST row of the group and the rest
              // indent past it, so the section is marked without spending a
              // whole row on a heading.
              groupIcon: choice == groups[g].choices.first
                  ? groups[g].icon
                  : null,
              selected: choice.value == selected,
            ),
          ),
      ],
      if (onFooter != null)
        PopupMenuItem<AnalogChoice<T>>(
          enabled: false,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AnalogSpace.smPx),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnalogIconButton(
              icon: footerIcon ?? Icons.add,
              tooltip: footerTooltip ?? 'Add',
              onPressed: () {
                Navigator.of(context).pop();
                onFooter();
              },
            ),
          ),
        ),
    ],
  );
  if (chosen != null) onSelected(chosen.value);
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.groupIcon,
    required this.selected,
  });

  final AnalogChoice<T> choice;
  final IconData? groupIcon;
  final bool selected;

  /// The gutter the group icon lives in. Rows without one indent past it so
  /// every label in a group starts on the same vertical.
  static const double _gutter = 26;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _gutter,
          child: groupIcon == null
              ? null
              : Icon(groupIcon, size: 15, color: AnalogColor.inkFaint),
        ),
        Expanded(
          child: Text(
            choice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AnalogType.sansFamily,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AnalogColor.ink : AnalogColor.inkDim,
            ),
          ),
        ),
        if (choice.detail != null) ...[
          const SizedBox(width: AnalogSpace.smPx),
          Text(
            choice.detail!,
            style: const TextStyle(
              fontFamily: AnalogType.monoFamily,
              fontSize: 10.5,
              color: AnalogColor.inkFaint,
            ),
          ),
        ],
        const SizedBox(width: AnalogSpace.smPx),
        if (choice.onDelete != null)
          // Deepest recognizer wins the tap, so this takes the hit rather than
          // the PopupMenuItem's own InkWell underneath it. Pops first: calling
          // onDelete with the menu still open would leave a route showing a
          // row that no longer exists.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.of(context).pop();
              choice.onDelete!();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: AnalogSpace.xsPx),
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
        SizedBox(
          width: 18,
          child: selected
              ? const Icon(Icons.check, size: 15, color: AnalogColor.ink)
              : null,
        ),
      ],
    );
  }
}
