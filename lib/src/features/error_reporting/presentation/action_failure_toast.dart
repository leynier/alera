import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('UserActions');

/// Reports a failed user action: logs the error with its stack trace and shows
/// one error toast that reads `Could not <action>: <cause>`.
///
/// [action] is the lowercase verb phrase, such as `archive workspace`. When
/// [context] is given and no longer mounted the toast is skipped, but the
/// failure is still logged.
void showActionFailure({
  required String action,
  required Object error,
  StackTrace? stackTrace,
  BuildContext? context,
}) {
  _logger.warning('Could not ${action.trim()}', error, stackTrace);
  if (context != null && !context.mounted) {
    return;
  }
  AleraToast.publish(
    message: actionFailureMessage(action, error),
    tone: AleraToastTone.error,
  );
}

/// Reports a failure whose cause already says everything, without a
/// `Could not ...` lead.
void showErrorToast({
  required Object error,
  StackTrace? stackTrace,
  BuildContext? context,
  String? fallback,
}) {
  _logger.warning('User-visible failure', error, stackTrace);
  if (context != null && !context.mounted) {
    return;
  }
  AleraToast.publish(
    message: userFacingErrorMessage(error, fallback: fallback),
    tone: AleraToastTone.error,
  );
}
