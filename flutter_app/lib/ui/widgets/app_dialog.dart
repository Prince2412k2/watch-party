import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../palette.dart';
import '../tokens.dart';
import 'app_button.dart';

/// FROZEN CONTRACT (PLAN §3.6). A modal surface, rebuilt on shadcn's
/// `sc.AlertDialog` + `sc.showDialog` (scale+fade in, acrylic backdrop). [show]
/// stays the stable entry point and keeps returning a `Future<T?>`.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.body,
    this.actions = const [],
    this.child,
  });

  final String title;
  final String? body;
  final List<Widget> actions;
  final Widget? child;

  /// Convenience presenter — now routes through shadcn's dialog so it inherits
  /// the acrylic backdrop + theme.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? body,
    List<Widget> actions = const [],
    Widget? child,
  }) {
    return sc.showDialog<T>(
      context: context,
      builder: (_) =>
          AppDialog(title: title, body: body, actions: actions, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return sc.AlertDialog(
      surfaceBlur: AppBlur.overlay,
      surfaceOpacity: 0.9,
      title: Text(title, style: kDialogTitleStyle.copyWith(color: wp.text)),
      content: (body != null || child != null)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (body != null)
                  Text(
                    body!,
                    style: TextStyle(color: wp.dim, fontSize: 14, height: 1.5),
                  ),
                if (child != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  child!,
                ],
              ],
            )
          : null,
      actions: actions.isEmpty ? null : actions,
    );
  }
}

/// Local title style (kept here to avoid a theme import cycle in the stub).
const TextStyle kDialogTitleStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: AppColors.text,
  letterSpacing: -0.3,
);

/// A tiny confirm helper many epics will reuse.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? body,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await AppDialog.show<bool>(
    context,
    title: title,
    body: body,
    actions: [
      AppButton(
        label: 'Cancel',
        variant: AppButtonVariant.ghost,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      AppButton(
        label: confirmLabel,
        variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return result ?? false;
}
