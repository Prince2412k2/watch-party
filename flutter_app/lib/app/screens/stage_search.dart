import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../analog/chrome/analog_text_field.dart';
import '../../models/models.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/palette.dart';
import '../../ui/widgets/desktop_window_chrome.dart';
import 'title_layout.dart';

/// The search control at the top of a browse stage.
///
/// A button until you want it. It sits in the band above the copy, on the
/// left, where the stage has nothing else — and a field parked open across
/// that band reads as a toolbar on a surface that does not have one. So it is
/// a glyph, and it opens into the field, the same way the profile handle in
/// the opposite corner opens into its tray.
///
/// It closes itself when it has nothing in it and you look away. It does NOT
/// close while a query is typed: the field is the only thing on screen saying
/// why the rail is short, and collapsing it would hide the reason the library
/// looks half empty.
class StageSearchField extends StatefulWidget {
  const StageSearchField({
    super.key,
    required this.hint,
    required this.query,
    required this.onChanged,
    this.controller,
  });

  final String hint;

  /// The live query, for the clear affordance and for deciding whether the
  /// tray may close. The text itself lives in [controller] — this widget does
  /// not own it, because clearing has to move the field's own text, not just
  /// the caller's copy of it.
  final String query;

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// The open field. The collapsed button is [_button] across.
  static const double width = 340;

  @override
  State<StageSearchField> createState() => _StageSearchFieldState();
}

class _StageSearchFieldState extends State<StageSearchField>
    with SingleTickerProviderStateMixin {
  /// Built in initState rather than as a `late final` initialiser: a lazy
  /// field is created on first READ, and dispose reads it.
  late final AnimationController _tray;
  final _focus = FocusNode(debugLabel: 'stageSearch');

  /// The collapsed circle.
  static const double _button = 48;

  /// The tray. Taller than the glyph because the field inside it is ~49 and
  /// its exact height comes from text metrics — a tray pinned to the button's
  /// size clipped it by a fraction of a pixel, which reads as a hairline of
  /// missing border rather than as anything explicable.
  static const double _height = 54;

  bool get _open => _tray.value > 0;

  @override
  void initState() {
    super.initState();
    _tray = AnimationController(
      vsync: this,
      duration: AnalogMotion.drawerMs,
      reverseDuration: AnalogMotion.exitMs,
    );
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _tray.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _closeIfEmpty();
  }

  void _open_() {
    if (_open) return;
    _tray.forward();
    // After the frame, so the field exists to take it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _closeIfEmpty() {
    if (widget.query.isNotEmpty) return;
    _tray.reverse();
  }

  void _toggle() {
    if (!_open) return _open_();
    _focus.unfocus();
    _closeIfEmpty();
  }

  void _clear() {
    widget.controller?.clear();
    widget.onChanged('');
    _focus.unfocus();
    _tray.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return TapRegion(
      onTapOutside: (_) => _closeIfEmpty(),
      child: AnimatedBuilder(
        animation: _tray,
        builder: (context, _) {
          final t = AnalogMotion.drawerEase.transform(
            _tray.value.clamp(0.0, 1.0),
          );
          final width = _button + (StageSearchField.width - _button) * t;

          return SizedBox(
            width: width,
            height: _height,
            child: Stack(
              children: [
                // The field is laid out at its FULL width the whole time and
                // clipped to the tray, so opening slides it out from under
                // the glyph instead of reflowing its contents every frame.
                if (t > 0)
                  Positioned.fill(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        maxWidth: StageSearchField.width,
                        child: Opacity(
                          opacity: t,
                          child: SizedBox(
                            width: StageSearchField.width,
                            child: AnalogTextField(
                              controller: widget.controller,
                              focusNode: _focus,
                              hint: widget.hint,
                              onChanged: widget.onChanged,
                              textInputAction: TextInputAction.search,
                              leading: Icon(
                                Icons.search,
                                size: 18,
                                color: wp.dim,
                              ),
                              trailing: widget.query.isEmpty
                                  ? null
                                  : _ClearButton(onTap: _clear),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // The glyph. Fades out as the field takes over, and stops
                // taking taps once it has — otherwise it sits on top of the
                // text you are trying to click into.
                if (t < 1)
                  Positioned(
                    left: 0,
                    top: (_height - _button) / 2,
                    child: Opacity(
                      opacity: 1 - t,
                      child: IgnorePointer(
                        ignoring: t > 0,
                        child: _SearchButton(size: _button, onTap: _toggle),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The collapsed state: a glyph on the stage, nothing else.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: 'Search',
      child: Material(
        color: wp.surface,
        shape: CircleBorder(side: BorderSide(color: wp.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.search, size: 18, color: wp.text),
          ),
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
