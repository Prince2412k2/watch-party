import 'package:flutter/material.dart';

/// FROZEN CONTRACT (PLAN §3.6). A flat dimming overlay behind dialogs / over
/// posters. No blur (glass was explicitly removed from the system).
class Scrim extends StatelessWidget {
  const Scrim({super.key, this.opacity = 0.6, this.onTap, this.child});

  final double opacity;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: opacity),
        child: child == null ? const SizedBox.expand() : Center(child: child),
      ),
    );
  }
}
