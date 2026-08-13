import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/analog_tokens.dart';
import 'analog_dialog.dart';
import 'analog_panel.dart';

/// One selectable row in the palette.
@immutable
class AnalogCommandItem {
  const AnalogCommandItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.trailing,
    this.preview,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;

  /// A short right-aligned readout — a year, a shortcut, a count.
  final String? trailing;

  /// What to show beside the list while this row is the highlighted one — a
  /// poster, typically. Only ever asked for when the palette was opened with
  /// `previewPane: true`; a row without one leaves the pane empty rather than
  /// letting the previous row's poster stand in for it.
  ///
  /// A builder rather than a widget because this is built once per frame for
  /// exactly one row, not eagerly for every match in the library.
  final WidgetBuilder? preview;
}

/// A titled group of [AnalogCommandItem]s.
@immutable
class AnalogCommandCategory {
  const AnalogCommandCategory({required this.title, required this.items});

  final String title;
  final List<AnalogCommandItem> items;
}

/// Produces results for a query. Successive yields **accumulate**, so a builder
/// can put an instant local list on screen and append a slower remote one
/// without the first disappearing and coming back.
typedef AnalogCommandResults =
    Stream<List<AnalogCommandCategory>> Function(String query);

/// Open the command palette.
///
/// There is no Material equivalent to drop in here, so this is the one surface
/// in the kit built from nothing: a sheet, a search line, and a flat list of
/// rows under category headings.
///
/// Every path through it is keyboard-first, because both of its entry points
/// are keys (Ctrl/Cmd-K and `/`) and a palette you have to reach for the mouse
/// to finish is worse than no palette. Up/Down move the highlight, Enter runs
/// it, Escape closes. The highlight is a filled plate with a detent bar down
/// its leading edge — position and weight, not a tint.
///
/// With [previewPane] it is fzf: the matches down the left, and what the
/// highlight is currently sitting on shown at size on the right, changing as
/// the highlight moves. On a window under 720 logical pixels the pane is
/// dropped and the list gets the sheet to itself.
Future<void> showAnalogCommandPalette({
  required BuildContext context,
  required AnalogCommandResults results,
  Duration debounce = const Duration(milliseconds: 140),
  String hint = 'Search',
  bool previewPane = false,
}) {
  return showAnalogDialog<void>(
    context: context,
    barrierLabel: 'Close the command palette',
    builder: (context) => _CommandPalette(
      results: results,
      debounce: debounce,
      hint: hint,
      previewPane: previewPane,
    ),
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({
    required this.results,
    required this.debounce,
    required this.hint,
    required this.previewPane,
  });

  final AnalogCommandResults results;
  final Duration debounce;
  final String hint;
  final bool previewPane;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _input = FocusNode(
    debugLabel: 'AnalogCommandPalette',
    onKeyEvent: _onKey,
  );

  Timer? _debounce;
  StreamSubscription<List<AnalogCommandCategory>>? _subscription;
  List<AnalogCommandCategory> _categories = const [];
  int _highlight = 0;

  /// The flat activation order — what Up/Down actually walk. Category headings
  /// are not stops.
  List<AnalogCommandItem> get _flat => [
    for (final category in _categories) ...category.items,
  ];

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.cancel();
    _controller.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => _run(query));
  }

  void _run(String query) {
    _subscription?.cancel();
    setState(() {
      _categories = const [];
      _highlight = 0;
    });
    _subscription = widget.results(query).listen(
      (delta) {
        if (!mounted || delta.isEmpty) return;
        setState(() => _categories = [..._categories, ...delta]);
      },
      // A failing result source must not take the palette down with it — the
      // categories already on screen stay usable.
      onError: (Object _) {},
    );
  }

  void _move(int delta) {
    final count = _flat.length;
    if (count == 0) return;
    setState(() => _highlight = (_highlight + delta) % count);
    if (_highlight < 0) _highlight += count;
  }

  void _activate() {
    final items = _flat;
    if (_highlight < 0 || _highlight >= items.length) return;
    items[_highlight].onSelected();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _activate();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    var index = 0;
    final rows = <Widget>[];
    for (final category in _categories) {
      rows.add(_CategoryHeading(title: category.title));
      for (final item in category.items) {
        final i = index++;
        rows.add(
          _CommandRow(
            item: item,
            highlighted: i == _highlight,
            onHover: () => setState(() => _highlight = i),
            onTap: item.onSelected,
          ),
        );
      }
    }

    // fzf's two panes: the matches on the left, what the highlight is sitting
    // on to the right of them. Decided by the CALLER, not by whether the
    // current matches happen to carry a preview — deriving it from the results
    // resized the sheet under the reader's hands the moment typing turned the
    // pane on. Dropped on a window too narrow to hold both, where the list is
    // what the pixels are worth spending on.
    final flat = _flat;
    final showPreview = widget.previewPane && media.size.width >= 720;
    final highlighted = _highlight >= 0 && _highlight < flat.length
        ? flat[_highlight]
        : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AnalogSpace.xlPx),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: showPreview ? 820 : 560,
            maxHeight: (media.size.height * 0.7).clamp(240.0, 520.0),
          ),
          child: AnalogPanel(
            radius: AnalogRadius.sheetPx,
            lift: AnalogLift.over,
            border: AnalogColor.lineStrong,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AnalogSpace.lgPx,
                    AnalogSpace.mdPx,
                    AnalogSpace.lgPx,
                    AnalogSpace.mdPx,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 17,
                        color: AnalogColor.inkFaint,
                      ),
                      const SizedBox(width: AnalogSpace.mdPx),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _input,
                          autofocus: true,
                          onChanged: _onQueryChanged,
                          cursorColor: AnalogColor.ink,
                          cursorWidth: AnalogPoster.framePx * 2,
                          cursorRadius: Radius.zero,
                          style: const TextStyle(
                            fontFamily: AnalogType.sansFamily,
                            fontSize: 15,
                            color: AnalogColor.ink,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: widget.hint,
                            hintStyle: const TextStyle(
                              fontFamily: AnalogType.sansFamily,
                              fontSize: 15,
                              color: AnalogColor.inkFaint,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: AnalogPoster.framePx,
                  thickness: AnalogPoster.framePx,
                  color: AnalogColor.line,
                ),
                Flexible(
                  child: showPreview
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _list(rows, _scroll)),
                            const VerticalDivider(
                              width: AnalogPoster.framePx,
                              thickness: AnalogPoster.framePx,
                              color: AnalogColor.line,
                            ),
                            SizedBox(
                              width: 260,
                              child: _Preview(item: highlighted),
                            ),
                          ],
                        )
                      : _list(rows, _scroll),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The match list. Extracted because it renders either alone or as the left
/// half of the two-pane layout, and the two must not drift apart.
Widget _list(List<Widget> rows, ScrollController scroll) => Builder(
  builder: (context) => rows.isEmpty
      ? const Padding(
          padding: EdgeInsets.all(AnalogSpace.xlPx),
          child: Text(
            'No matches',
            style: TextStyle(
              fontFamily: AnalogType.sansFamily,
              fontSize: 13,
              color: AnalogColor.inkFaint,
            ),
          ),
        )
      : ListView(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: AnalogSpace.smPx),
          // Hugs its content when it is the whole sheet; the two-pane layout
          // stretches it, and then this costs nothing.
          shrinkWrap: true,
          children: rows,
        ),
);

/// The right pane: whatever the highlighted row wants shown for itself.
///
/// A row with nothing to show (the quick-nav entries) leaves it empty rather
/// than holding the last poster, which would say the highlight was somewhere it
/// is not.
class _Preview extends StatelessWidget {
  const _Preview({required this.item});

  final AnalogCommandItem? item;

  @override
  Widget build(BuildContext context) {
    final builder = item?.preview;
    return Padding(
      padding: const EdgeInsets.all(AnalogSpace.lgPx),
      child: Center(
        child: builder == null
            ? const Icon(
                Icons.image_outlined,
                size: 22,
                color: AnalogColor.lineStrong,
              )
            : builder(context),
      ),
    );
  }
}

class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AnalogSpace.lgPx,
      AnalogSpace.mdPx,
      AnalogSpace.lgPx,
      AnalogSpace.xsPx,
    ),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontFamily: AnalogType.sansFamily,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AnalogColor.inkFaint,
      ),
    ),
  );
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.item,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final AnalogCommandItem item;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: highlighted,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AnalogMotion.detentMs,
            curve: AnalogMotion.detentEase,
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(
              horizontal: AnalogSpace.lgPx - AnalogHairline.idlePx,
              vertical: AnalogSpace.smPx,
            ),
            decoration: BoxDecoration(
              color: highlighted
                  ? AnalogColor.stageSurface2
                  : const Color(0x00000000),
              // The detent runs down the leading edge of the highlighted row:
              // the highlight is a position and a weight before it is a fill.
              border: Border(
                left: BorderSide(
                  width: AnalogHairline.idlePx,
                  color: highlighted
                      ? AnalogColor.ink
                      : const Color(0x00000000),
                ),
              ),
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 16,
                    color: highlighted
                        ? AnalogColor.ink
                        : AnalogColor.inkFaint,
                  ),
                  const SizedBox(width: AnalogSpace.mdPx),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AnalogType.sansFamily,
                      fontSize: 13.5,
                      fontWeight: highlighted
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: highlighted
                          ? AnalogColor.ink
                          : AnalogColor.inkDim,
                    ),
                  ),
                ),
                if (item.trailing != null) ...[
                  const SizedBox(width: AnalogSpace.mdPx),
                  Text(
                    item.trailing!,
                    style: const TextStyle(
                      fontFamily: AnalogType.monoFamily,
                      fontSize: 11.5,
                      color: AnalogColor.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
