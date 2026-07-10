import 'package:flutter/material.dart';

import '../tokens.dart';
import 'app_button.dart';

/// FROZEN CONTRACT (PLAN §3.6). A minimal modal surface. E1 refines visuals;
/// [show] is the stable entry point.
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

  /// Convenience presenter.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? body,
    List<Widget> actions = const [],
    Widget? child,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => AppDialog(title: title, body: body, actions: actions, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        margin: const EdgeInsets.all(AppSpacing.xl),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: kDialogTitleStyle),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(body!, style: const TextStyle(color: AppColors.dim, fontSize: 14, height: 1.5)),
            ],
            if (child != null) ...[const SizedBox(height: AppSpacing.lg), child!],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final a in actions) ...[a, const SizedBox(width: AppSpacing.sm)],
                ],
              ),
            ],
          ],
        ),
      ),
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
      AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, onPressed: () => Navigator.of(context).pop(false)),
      AppButton(
        label: confirmLabel,
        variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return result ?? false;
}
