import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../tokens.dart';

/// Semantic tone for [AppChip]. [neutral] is the default surface chip (genre,
/// filter, tag). [live]/[danger] use the single reserved red. [success] uses
/// the sparse green tick color.
enum AppChipTone { neutral, live, danger, success }

/// A small flat label pill — genre tags, quality badges, the LIVE/REC dot,
/// filter toggles. Rebuilt on shadcn: interactive/neutral chips use `sc.Chip`
/// (outline when idle, secondary fill when selected); status tones render as an
/// `sc.OutlineBadge` so the monochrome frame stays and only the reserved
/// red/green shows through the dot + label. Signature is frozen.
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
      AppChipTone.neutral => (selected ? AppColors.text : AppColors.dim, null),
      AppChipTone.live => (AppColors.red, AppColors.live),
      AppChipTone.danger => (AppColors.red, null),
      AppChipTone.success => (AppColors.green, null),
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

    final content = Text(
      label,
      style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
    );

    if (tone == AppChipTone.neutral) {
      return sc.Chip(
        onPressed: onTap,
        style: selected
            ? sc.ButtonVariance.secondary
            : sc.ButtonVariance.outline,
        leading: leading,
        child: content,
      );
    }

    // Status tones are non-interactive labels.
    return sc.OutlineBadge(leading: leading, child: content);
  }
}
