import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_toast.dart';
import '../../state/offline_provider.dart';
import 'app_dialog.dart';

/// Use the same confirmation and failure behavior from every download surface.
Future<void> removeLocalDownload(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  required String title,
}) async {
  final confirmed = await showConfirm(
    context,
    title: 'Remove download?',
    body: '$title will be deleted from this device.',
    confirmLabel: 'Remove',
    danger: true,
  );
  if (!confirmed || !context.mounted) return;
  try {
    await ref.read(offlineProvider.notifier).remove(itemId);
    if (context.mounted) showAnalogToast(context, 'Download removed');
  } catch (_) {
    if (context.mounted) {
      showAnalogToast(
        context,
        'Could not remove the download. Try again.',
        tone: AnalogToastTone.danger,
      );
    }
  }
}
