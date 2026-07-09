import 'package:flutter/material.dart';

import '../tokens.dart';

/// Button variants in the cinematic-minimal system.
/// - [primary]: near-white pill, dark text (the "Play" affordance).
/// - [secondary]: solid surface, hairline border (quiet default).
/// - [ghost]: text-only, brightens on hover.
/// - [danger]: red-tinted, for destructive actions.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// FROZEN CONTRACT (PLAN §3.6). E1 makes it pretty; the signature is fixed.
class AppButton extends StatefulWidget {
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
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null && !widget.busy;
    var (bg, fg, border) = switch (widget.variant) {
      AppButtonVariant.primary => (AppColors.accent, AppColors.onAccent, null as Color?),
      AppButtonVariant.secondary => (AppColors.surface, AppColors.text, AppColors.line),
      AppButtonVariant.ghost => (Colors.transparent, AppColors.dim, null),
      AppButtonVariant.danger => (const Color(0x1AE0655E), AppColors.red, const Color(0x4DE0655E)),
    };

    if (_hover && !disabled) {
      bg = switch (widget.variant) {
        AppButtonVariant.primary => AppColors.accentDim,
        AppButtonVariant.secondary => AppColors.surface2,
        AppButtonVariant.ghost => Colors.transparent,
        AppButtonVariant.danger => const Color(0x2AE0655E),
      };
      if (widget.variant == AppButtonVariant.ghost) fg = AppColors.text;
    }

    if (disabled) {
      fg = AppColors.faint;
    }

    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(widget.label,
            style: TextStyle(
                color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ],
    );

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: widget.busy ? null : widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
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
      ),
    );
  }
}
