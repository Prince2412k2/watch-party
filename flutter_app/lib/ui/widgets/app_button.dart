import 'package:flutter/widgets.dart';

import '../../analog/chrome/analog_button.dart';

/// Button variants in the analog system.
/// - [primary]: the ink-coloured plate, dark label (the "Play" affordance).
/// - [secondary]: surface plate, hairline frame (quiet default).
/// - [ghost]: label only until reached.
/// - [danger]: reserved red plus a doubled frame, for destructive actions.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// FROZEN CONTRACT (PLAN §3.6). The public signature
/// (label/onPressed/variant/icon/busy/expand) is unchanged; only what draws it
/// moved. [AnalogButton] owns hover/press/focus/disabled now, painting on the
/// generated tokens rather than on a component library's theme bridge.
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
    return AnalogButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      busy: busy,
      expand: expand,
      tone: switch (variant) {
        AppButtonVariant.primary => AnalogButtonTone.primary,
        AppButtonVariant.secondary => AnalogButtonTone.secondary,
        AppButtonVariant.ghost => AnalogButtonTone.ghost,
        AppButtonVariant.danger => AnalogButtonTone.danger,
      },
    );
  }
}
