import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// FROZEN CONTRACT (PLAN §3.6). A dimming overlay behind dialogs / over posters.
/// Now optionally acrylic: pass [blur] to add a backdrop blur (the RGBA window
/// makes this viable). Signature is frozen except the ADDITIVE [blur]/
/// [blurSigma] (PLAN allows this) — default `blur: false` keeps the flat scrim.
class Scrim extends StatelessWidget {
  const Scrim({
    super.key,
    this.opacity = 0.6,
    this.onTap,
    this.child,
    this.blur = false,
    this.blurSigma,
  });

  final double opacity;
  final VoidCallback? onTap;
  final Widget? child;

  /// When true, blurs whatever is painted behind the scrim (acrylic).
  final bool blur;

  /// Blur radius when [blur] is true; defaults to [AppBlur.scrim].
  final double? blurSigma;

  @override
  Widget build(BuildContext context) {
    Widget overlay = ColoredBox(
      color: Colors.black.withValues(alpha: opacity),
      child: child == null ? const SizedBox.expand() : Center(child: child),
    );

    if (blur) {
      final sigma = blurSigma ?? AppBlur.scrim;
      overlay = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: overlay,
      );
    }

    return GestureDetector(onTap: onTap, child: overlay);
  }
}
