import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

/// Button variants in the cinematic-minimal system.
/// - [primary]: near-white pill, dark text (the "Play" affordance).
/// - [secondary]: solid surface, hairline border (quiet default).
/// - [ghost]: text-only, brightens on hover.
/// - [danger]: red-tinted, for destructive actions.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// FROZEN CONTRACT (PLAN §3.6). Rebuilt on `sc.Button` variants; the public
/// signature (label/onPressed/variant/icon/busy/expand) is unchanged. shadcn
/// owns the hover/press/focus states now, themed by [AppShadcnTheme].
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
    final onTap = busy ? null : onPressed;
    final Widget? leading = busy
        ? const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (icon != null ? Icon(icon, size: 18) : null);

    final child = Text(label);

    final button = switch (variant) {
      AppButtonVariant.primary => sc.Button.primary(
        onPressed: onTap,
        leading: leading,
        child: child,
      ),
      AppButtonVariant.secondary => sc.Button.secondary(
        onPressed: onTap,
        leading: leading,
        child: child,
      ),
      AppButtonVariant.ghost => sc.Button.ghost(
        onPressed: onTap,
        leading: leading,
        child: child,
      ),
      AppButtonVariant.danger => sc.Button.destructive(
        onPressed: onTap,
        leading: leading,
        child: child,
      ),
    };

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
