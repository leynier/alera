import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

/// The host lacks `runsV1` (or `recipesV1` for recipes); never guessed.
class RunsUpdateRequired implements Exception {
  const RunsUpdateRequired({this.recipes = false});

  final bool recipes;

  @override
  String toString() => recipes
      ? 'Update the runtime to manage recipes.'
      : 'Update the runtime to use runs.';
}

/// Whether [error] means the decision was made against an outdated read.
bool isRunStaleError(Object? error) =>
    error is TerminalHostConflictException &&
    (error.code == 'gate_stale' ||
        error.code == 'run_sequence_stale' ||
        error.code == 'gate_not_pending' ||
        error.code == 'gate_not_due');

/// Sentence-case text for a failed run request, keyed by the host's code.
String runErrorMessage(Object error) {
  if (error is RunsUpdateRequired) return error.toString();
  if (error is TerminalHostConflictException) {
    return switch (error.code) {
      'gate_stale' || 'gate_not_due' =>
        'This gate changed while you were reading. Refresh before deciding.',
      'gate_not_pending' => 'Someone already resolved this gate.',
      'gate_not_found' => 'This gate no longer exists.',
      'gate_invalid_resolution' =>
        'That answer is not one of the gate options.',
      'gate_not_resolvable' => 'This gate cannot be resolved here.',
      'run_not_found' => 'This run no longer exists.',
      'run_sequence_stale' =>
        'The run changed while you were reading. Refresh and try again.',
      'run_finished' => 'This run has already finished.',
      'run_gate_pending' => 'Resolve the pending gate before resuming.',
      'run_reason_required' => 'Add a note that explains the change.',
      'run_has_active_work' =>
        'Wait for running tasks to finish before requesting changes.',
      'run_integration_pending' =>
        'Wait for the pending integration to settle first.',
      'run_nothing_to_retry' => 'There is nothing to retry.',
      'run_retry_unavailable' =>
        'This task cannot be retried right now. Pause the run first.',
      'run_workspace_busy' => 'Another run already uses this workspace.',
      'run_not_isolated' => 'Only isolated runs support this action.',
      'run_not_paused' => 'Pause the run first.',
      'run_not_running' => 'The run is not running.',
      'run_request_conflict' =>
        'This request was already used for a different action. Try again.',
      _ => error.message,
    };
  }
  if (error is TerminalHostConnectionClosedException) {
    return 'The Alera runtime is not reachable.';
  }
  return error.toString();
}
