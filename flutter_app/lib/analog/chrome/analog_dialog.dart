import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';
import 'analog_panel.dart';

/// Present [builder] as a modal on the analog stage.
///
/// Built on [showGeneralDialog] rather than a component library's own presenter
/// so the route is a real Flutter [ModalRoute]: Escape dismisses it, the
/// barrier dismisses it, `Navigator.pop` returns through it, and it participates
/// in the router's stack like everything else. Only the paint and the motion
/// belong to this file.
///
/// The entrance is a fade with a two-percent settle on [AnalogMotion.drawerMs]
/// — restrained, weighted, no overshoot — and collapses to a plain fade when
/// the platform asks for reduced motion.
Future<T?> showAnalogDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String barrierLabel = 'Dismiss',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: AnalogColor.backdropScrim,
    transitionDuration: AnalogMotion.drawerMs,
    pageBuilder: (context, animation, secondary) => builder(context),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AnalogMotion.drawerEase,
        reverseCurve: AnalogMotion.drawerEase,
      );
      final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final faded = FadeTransition(opacity: curved, child: child);
      if (reduceMotion) return faded;
      return ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
        child: faded,
      );
    },
  );
}

/// The kit's modal surface.
///
/// A sheet, so [AnalogRadius.sheetPx] applies — the one radius above chrome and
/// still nowhere near artwork. Actions sit on the trailing edge in a wrap, so a
/// narrow window stacks them instead of clipping the confirm button off the
/// end.
class AnalogDialog extends StatelessWidget {
  const AnalogDialog({
    super.key,
    required this.title,
    this.body,
    this.actions = const [],
    this.child,
    this.maxWidth = 460,
  });

  final String title;
  final String? body;
  final List<Widget> actions;
  final Widget? child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AnalogSpace.xlPx),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: media.size.height - AnalogSpace.xxlPx * 2,
            ),
            child: AnalogPanel(
              radius: AnalogRadius.sheetPx,
              lift: AnalogLift.over,
              border: AnalogColor.lineStrong,
              padding: const EdgeInsets.all(AnalogSpace.xlPx),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AnalogType.sansFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: AnalogColor.ink,
                    ),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: AnalogSpace.mdPx),
                    Text(
                      body!,
                      style: const TextStyle(
                        fontFamily: AnalogType.sansFamily,
                        color: AnalogColor.inkDim,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (child != null) ...[
                    const SizedBox(height: AnalogSpace.lgPx),
                    Flexible(child: SingleChildScrollView(child: child!)),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: AnalogSpace.xlPx),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AnalogSpace.smPx,
                        runSpacing: AnalogSpace.smPx,
                        children: actions,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
