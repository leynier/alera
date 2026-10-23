import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';
import 'package:alera/src/features/error_reporting/presentation/action_failure_toast.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

final Logger _logger = Logger('WorkspaceRelocation');

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
    } catch (error, stackTrace) {
      if (!context.mounted) {
        // The controller leaves reporting a relocation failure to this flow,
        // so it must not vanish with the screen that started it.
        showActionFailure(
          action: action.toLowerCase(),
          error: error,
          stackTrace: stackTrace,
        );
        return false;
      }
      _logger.warning('Could not ${action.toLowerCase()}', error, stackTrace);
      final retry = await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: 'Retry $action?',
          message:
              '${userFacingErrorMessage(error)}\n\nRetry resumes the same transfer with the choices you confirmed. A completed transfer will not repeat its Git changes. Resolve any reported blocker before retrying.',
          confirmLabel: 'Retry',
          cancelLabel: 'Close',
        ),
      );
      if (retry != true) return false;
    }
  }
  return false;
}
