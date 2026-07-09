import 'package:flutter/material.dart';

import '../tokens.dart';

/// Button variants in the cinematic-minimal system.
/// - [primary]: near-white pill, dark text (the "Play" affordance).
/// - [secondary]: solid surface, hairline border (quiet default).
/// - [ghost]: text-only, brightens on hover.
/// - [danger]: red-tinted, for destructive actions.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// FROZEN CONTRACT (PLAN §3.6). E1 makes it pretty; the signature is fixed.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.icon,
    this.busy = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      AppButtonVariant.primary => (AppColors.accent, AppColors.onAccent, null),
      AppButtonVariant.secondary => (AppColors.surface, AppColors.text, AppColors.line),
      AppButtonVariant.ghost => (Colors.transparent, AppColors.dim, null),
      AppButtonVariant.danger => (const Color(0x1AE0655E), AppColors.red, const Color(0x4DE0655E)),
    };

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(label,
            style: TextStyle(
                color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ],
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: busy ? null : onPressed,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: border == null
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  border: Border.all(color: border),
                ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
