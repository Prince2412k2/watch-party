import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Assert that no rounding of any kind reaches poster artwork inside [scope].
///
/// `poster.radiusPx` is 0 in `app/shared/design/analog-tokens.json` and both
/// clients assert it there — but a token being zero does not stop a widget
/// hard-coding `BorderRadius.circular(12)`, which is exactly what every poster
/// in this tree did before #66 (`poster_card.dart:88,129`, `still_card.dart:50,
/// 90`, `view_card.dart:59,64`, `download_poster.dart:39`, and the skeletons).
/// So the invariant is checked where it can actually be broken: on the rendered
/// widget tree.
///
/// `AnalogRadius.chromePx/sheetPx/pillPx` are legitimate on buttons, sheets and
/// toasts. They are simply never allowed in a subtree that paints artwork.
void expectSquareArtwork(WidgetTester tester, Finder scope) {
  final offenders = <String>[];

  void visit(Element element) {
    final radius = _radiusOf(element.widget);
    if (radius != null && radius != BorderRadius.zero) {
      offenders.add('${element.widget.runtimeType}: $radius');
    }
    element.visitChildren(visit);
  }

  for (final element in scope.evaluate()) {
    visit(element);
  }

  expect(
    offenders,
    isEmpty,
    reason:
        'poster artwork must be square and unrounded at every size, including '
        'skeletons, placeholders, season cards and selected states. Rounded: '
        '${offenders.join(', ')}',
  );
}

BorderRadius? _radiusOf(Widget widget) {
  if (widget is ClipRRect) {
    return widget.borderRadius.resolve(TextDirection.ltr);
  }
  if (widget is PhysicalModel) return widget.borderRadius;
  if (widget is Material) {
    return widget.borderRadius?.resolve(TextDirection.ltr);
  }
  if (widget is Container) return _fromDecoration(widget.decoration);
  if (widget is DecoratedBox) return _fromDecoration(widget.decoration);
  if (widget is AnimatedContainer) return _fromDecoration(widget.decoration);
  return null;
}

BorderRadius? _fromDecoration(Decoration? decoration) {
  if (decoration is BoxDecoration) {
    return decoration.borderRadius?.resolve(TextDirection.ltr);
  }
  if (decoration is ShapeDecoration) {
    final shape = decoration.shape;
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr);
    }
  }
  return null;
}
