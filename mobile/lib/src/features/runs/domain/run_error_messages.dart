import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';

/// The host was paired before runs existed. The phone never guesses at an
/// older contract.
class RunsUpdateRequired implements Exception {
  const RunsUpdateRequired();

  static const String message =
      'Update the runtime host, then reconnect. This host cannot provide runs safely.';

  @override
  String toString() => message;
}

/// The gate changed (new evidence, another device decided) since it was shown.
bool isStaleGateError(Object error) =>
    error is RuntimeRequestError &&
    (error.code == 'gate_stale' || error.code == 'gate_not_pending');

/// The run moved on (another device paused, resumed or cancelled it).
bool isStaleRunError(Object error) =>
    error is RuntimeRequestError && error.code == 'run_sequence_stale';

/// Sentence-case text for a run failure, keyed by the runtime's error code.
String runErrorMessage(Object? error) {
  if (error is RunsUpdateRequired) return RunsUpdateRequired.message;
  if (error is RuntimeRequestError) {
    return switch (error.code) {
      'gate_stale' =>
        'The evidence changed since you opened this gate. Review it again.',
      'gate_not_pending' => 'Someone already decided this gate.',
      'gate_not_due' => 'This gate is not ready for a decision yet.',
      'gate_not_found' => 'This gate no longer exists.',
      'gate_invalid_resolution' => 'Choose one of the offered answers.',
      'run_not_found' => 'This run no longer exists.',
      'run_sequence_stale' =>
        'The run changed on another device. Review it and try again.',
      'run_reason_required' => 'Add a note explaining the change.',
      'run_gate_pending' => 'Decide the pending gate before resuming.',
      'run_has_active_work' =>
        'Wait for running tasks to finish before requesting changes.',
      'run_integration_pending' =>
        'Wait for the integration in progress to settle.',
      'run_finished' => 'This run already finished.',
      'run_workspace_busy' => 'Another run already holds this workspace.',
      'run_not_isolated' => 'Only isolated runs keep worktrees to clean up.',
      'run_retry_unavailable' ||
      'run_nothing_to_retry' => 'There is nothing to retry right now.',
      'run_not_paused' => 'Pause the run first.',
      _ => userFacingErrorMessage(error),
    };
  }
  return userFacingErrorMessage(error);
}
