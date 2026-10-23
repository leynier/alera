import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('ActionFailure');

/// Records a failed user action in the log file.
///
/// Use it where the failure is shown some other way than a SnackBar (an
/// inline error, a dialog), because the screen changing is not a record.
void logActionFailure(String action, Object error, [StackTrace? stackTrace]) {
  _logger.warning('could not ${action.trim()}', error, stackTrace);
}

/// Logs a failed user action and reports it in a SnackBar as
/// `Could not <action>: <cause>`.
///
/// Takes the messenger rather than a context so a caller can capture it
/// before an await and still report after the widget that started the action
/// is gone. [message] replaces the sentence when a feature words a known
/// failure itself; the error is logged either way. A null [messenger] still
/// logs.
void showActionFailure(
  ScaffoldMessengerState? messenger, {
  required String action,
  required Object error,
  StackTrace? stackTrace,
  String? message,
}) {
  logActionFailure(action, error, stackTrace);
  messenger?.showSnackBar(
    SnackBar(content: Text(message ?? actionFailureMessage(action, error))),
  );
}
