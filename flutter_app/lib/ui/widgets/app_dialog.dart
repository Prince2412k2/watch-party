import 'package:flutter/widgets.dart';

import '../../analog/chrome/analog_dialog.dart';
import '../analog_tokens.dart';
import 'app_button.dart';

/// FROZEN CONTRACT (PLAN §3.6). A modal surface, now an [AnalogDialog] on an
/// ordinary [showGeneralDialog] route — so Escape, the barrier and
/// `Navigator.pop` all behave the way the rest of the router does. [show] stays
/// the stable entry point and keeps returning a `Future<T?>`.
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

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? body,
    List<Widget> actions = const [],
    Widget? child,
  }) {
    return showAnalogDialog<T>(
      context: context,
      builder: (_) =>
          AppDialog(title: title, body: body, actions: actions, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnalogDialog(
      title: title,
      body: body,
      actions: actions,
      child: child,
    );
  }
}

/// Local title style, kept for the callers that still reference it.
const TextStyle kDialogTitleStyle = TextStyle(
  fontFamily: AnalogType.sansFamily,
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: AnalogColor.ink,
  letterSpacing: -0.3,
);

/// A tiny confirm helper many epics reuse.
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
