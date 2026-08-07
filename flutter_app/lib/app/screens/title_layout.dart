import 'package:flutter/widgets.dart';

import '../../ui/theme.dart';

/// Placement shared by the Movies browse stage and the title detail page.
///
/// The two surfaces show the same block — genre breadcrumb, title, overview,
/// meta run, actions — and one transitions into the other. For that transition
/// to read as the page settling rather than as a cut, the block has to occupy
/// exactly the same rectangle on both sides. Not approximately: a few pixels of
/// drift in the left inset or the vertical centring is visible as a jump on the
/// text, which is the largest thing on screen.
///
/// So the numbers live here rather than as literals in two files. They were the
/// detail page's, and the browse stage was brought to them.
abstract final class TitleLayout {
  /// Inset from the stage edge to the copy column.
  static const double padLeft = 64;
  static const double padTop = 80;

  /// Room held below the copy. On the detail page this is the cast band; on the
  /// browse stage it is where the rail sits. Deliberately the same number on
  /// both, because it is what decides where the vertically-centred copy lands —
  /// reserving more on one side would move the title.
  static const double padBottom = 170;

  /// Between the copy column and whatever sits beside it: the poster on the
  /// detail page, the mode strip while browsing.
  static const double columnGap = 80;

  static const int copyFlex = 92;
  static const int asideFlex = 108;

  /// Measures the copy is held to. Prose wants a readable line length far
  /// short of a desktop stage's width.
  static const double copyMaxWidth = 650;
  static const double overviewMaxWidth = 590;
}


/// Type shared by the Movies browse stage and the title detail page.
///
/// Same argument as [TitleLayout]: the transition moves everything except the
/// text, so the text has to be set identically on both sides. A 40px bold
/// heading becoming a 52px light one mid-flight is the most visible break the
/// transition can have, because the title is the biggest thing on screen.
///
/// These resolve to the app's own styles rather than restating them, so the
/// browse stage follows the theme instead of carrying a private copy of it.
abstract final class TitleType {
  /// The title. Large and light — [AppTheme.displayLarge].
  static const TextStyle heading = AppTheme.displayLarge;

  /// Genre breadcrumb, and any other small uppercase run above the title.
  static final TextStyle breadcrumb = AppTheme.mono.copyWith(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.3,
  );

  /// The meta run under the overview.
  static final TextStyle meta = AppTheme.mono.copyWith(
    fontSize: 10,
    letterSpacing: 0.6,
  );

  /// Overview prose.
  static const TextStyle overview = AppTheme.body;

  /// The tagline, which the detail page does not show but the browse stage
  /// does. Sized against the body rather than invented, so it sits in the
  /// same scale as everything around it.
  static final TextStyle tagline = AppTheme.body.copyWith(
    fontSize: 15,
    height: 1.5,
    fontStyle: FontStyle.italic,
  );
}
