import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../analog/chrome/analog_text_field.dart';
import '../../models/models.dart';
import '../../ui/palette.dart';
import '../../ui/widgets/desktop_window_chrome.dart';
import 'title_layout.dart';

/// The search line at the top of a browse stage.
///
/// Narrow on purpose. It sits in the band above the copy, on the left, where the
/// stage has nothing else — the profile handle is in the opposite corner, and a
/// field run across the whole width would read as a toolbar on a surface that
/// does not have one.
class StageSearchField extends StatelessWidget {
  const StageSearchField({
    super.key,
    required this.hint,
    required this.query,
    required this.onChanged,
    this.controller,
  });

  final String hint;

  /// The live query, for the clear affordance. The text itself lives in
  /// [controller] — this widget does not own it, because clearing has to move
  /// the field's own text, not just the caller's copy of it.
  final String query;

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  static const double width = 340;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return SizedBox(
      width: width,
      child: AnalogTextField(
        controller: controller,
        hint: hint,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        leading: Icon(Icons.search, size: 18, color: wp.dim),
        trailing: query.isEmpty
            ? null
            : _ClearButton(
                onTap: () {
                  controller?.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// [StageSearchField] in a browse stage's top band. Mount inside a [Stack] over
/// the stage's content.
///
/// Laid OVER the stage rather than added to its column on purpose. The copy
/// block's rectangle is load-bearing — see the note at the top of
/// [TitleLayout] — and a field that took height out of that column would push
/// the title down on the browse stage only, so the transition into the detail
/// page would drop the text as it crossed.
class StageSearchOverlay extends StatelessWidget {
  const StageSearchOverlay({
    super.key,
    required this.hint,
    required this.query,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final String query;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// Above the copy's [TitleLayout.padTop], below the window's own chrome band.
  static const double top = 22;

  @override
  Widget build(BuildContext context) => Positioned(
    top: top,
    // Aligned with the copy column beneath it, except where the window's
    // controls reach further in than that.
    left: math.max(TitleLayout.padLeft, desktopLeadingControlInset),
    child: StageSearchField(
      hint: hint,
      query: query,
      onChanged: onChanged,
      controller: controller,
    ),
  );
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: 'Clear search',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.close, size: 15, color: wp.dim),
          ),
        ),
      ),
    );
  }
}

/// The titles in [items] whose name matches [query], in the order they came in.
///
/// Substring, case-insensitive, over what the rail is already holding — the
/// stage filters the shelf in front of you rather than running a server search
/// that would replace it with a different list. Trimmed so a trailing space
/// while typing does not empty the rail.
List<LibraryItem> searchTitles(List<LibraryItem> items, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return items;
  return items
      .where((item) => item.name.toLowerCase().contains(needle))
      .toList(growable: false);
}
