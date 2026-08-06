import 'package:flutter/widgets.dart';

import '../../analog/chrome/analog_badge.dart';
import '../../ui/analog_tokens.dart';

/// Semantic tone for [AppChip]. [neutral] is the default surface chip (genre,
/// filter, tag). [live]/[danger] use the single reserved red. [success] uses
/// the sparse green tick colour.
enum AppChipTone { neutral, live, danger, success }

/// A small flat label — genre tags, quality badges, the LIVE/REC dot, filter
/// toggles. Signature is frozen.
///
/// Interactive/neutral chips are an [AnalogChip], which is focusable and
/// Enter/Space-operable and marks selection with a filled plate, a doubled
/// hairline and a bolder label before it uses any colour. Status tones are
/// non-interactive, so they render as an [AnalogBadge.outline] whose monochrome
/// frame stays put and lets only the reserved red/green through the dot and the
/// label.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.tone = AppChipTone.neutral,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final AppChipTone tone;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (fg, dot) = switch (tone) {
      AppChipTone.neutral => (
        selected ? AnalogColor.ink : AnalogColor.inkDim,
        null,
      ),
      AppChipTone.live => (AnalogColor.statusDanger, AnalogColor.statusLive),
      AppChipTone.danger => (AnalogColor.statusDanger, null),
      AppChipTone.success => (AnalogColor.statusSuccess, null),
    };

    Widget? leading;
    if (dot != null) {
      leading = Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
      );
    } else if (icon != null) {
      leading = Icon(icon, size: 13, color: fg);
    }

    if (tone == AppChipTone.neutral) {
      return AnalogChip(
        label: label,
        leading: leading,
        selected: selected,
        onPressed: onTap,
      );
    }

    return AnalogBadge.outline(
      leading: leading,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AnalogType.sansFamily,
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
