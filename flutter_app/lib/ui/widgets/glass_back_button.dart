import 'dart:io';

import 'package:flutter/material.dart';

import '../palette.dart';
import 'desktop_window_chrome.dart';

/// The way back, on every surface that has one.
///
/// There were four of these: two identical private copies on the title and show
/// stages, a labelled pill on the Discover detail screen, and a plain icon
/// button inside the player's top bar. Four shapes in four places, one of which
/// also sat at a different height — so going back looked like a different
/// control depending on where you had got to, and the button moved under the
/// cursor as you crossed between them.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Across. Matches nothing else on purpose — it is the only round control on
  /// the left of the stage.
  static const double diameter = 40;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      // A chevron with no label. The player's button carried this and the
      // stages' copies did not, which is the sort of thing that only shows up
      // in a screen reader.
      message: 'Back',
      child: Material(
        color: wp.surface.withValues(alpha: 0.72),
        shape: CircleBorder(side: BorderSide(color: wp.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: diameter,
            child: Icon(Icons.chevron_left, size: 22, color: wp.text),
          ),
        ),
      ),
    );
  }
}

/// Where the back button sits, on every surface that has one.
///
/// One place for the numbers because the whole point is that they agree: a
/// button that shifts a few pixels between the title stage and the player reads
/// as the window jumping, not as a new screen.
abstract final class BackButtonPlacement {
  /// From the top of the stage.
  ///
  /// macOS keeps its traffic lights in the top-left of the CONTENT area, in a
  /// band [integratedDesktopChromeHeight] tall. Insetting from the left clears
  /// the lights themselves but leaves the button's top edge inside that band —
  /// visually cramped against them, and sitting in the strip the window uses for
  /// dragging. Dropping BELOW the band is what the chat drawer does, for the
  /// same reason.
  static double get top =>
      Platform.isMacOS ? integratedDesktopChromeHeight + 8 : 25;

  /// From the left edge, clear of the traffic lights where there are any.
  static double get left =>
      desktopLeadingControlInset > 0 ? desktopLeadingControlInset : 40;
}

/// [GlassBackButton] at [BackButtonPlacement], for a surface that stacks it over
/// its content. Mount inside a [Stack].
class StageBackButton extends StatelessWidget {
  const StageBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Positioned(
    top: BackButtonPlacement.top,
    left: BackButtonPlacement.left,
    child: GlassBackButton(onTap: onTap),
  );
}
