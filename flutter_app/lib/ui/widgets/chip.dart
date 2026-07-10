import 'package:flutter/material.dart';

import '../tokens.dart';

/// Semantic tone for [AppChip]. [neutral] is the default surface chip (genre,
/// filter, tag). [live]/[danger] use the single reserved red. [success] uses
/// the sparse green tick color.
enum AppChipTone { neutral, live, danger, success }

/// A small flat label pill — genre tags, quality badges, the LIVE/REC dot,
/// filter toggles. No gradients; selection is communicated by fill contrast.
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
    final bg = selected ? AppColors.surface3 : AppColors.surface;
    final border = selected ? AppColors.line2 : AppColors.line;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
