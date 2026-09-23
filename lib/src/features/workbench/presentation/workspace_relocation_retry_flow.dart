import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

Future<bool> runWorkspaceRelocationWithRetry({
  required BuildContext context,
  required String action,
  required Future<void> Function(String relocationId) perform,
}) async {
  final relocationId = const Uuid().v4();
  while (context.mounted) {
    try {
      await perform(relocationId);
      return true;
    } catch (error) {
      if (!context.mounted) return false;
      final retry = await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: 'Retry $action?',
          message:
              '$error\n\nRetry resumes the same transfer with the choices you confirmed. A completed transfer will not repeat its Git changes. Resolve any reported blocker before retrying.',
          confirmLabel: 'Retry',
          cancelLabel: 'Close',
        ),
      );
      if (retry != true) return false;
    }
  }
  return false;
}
