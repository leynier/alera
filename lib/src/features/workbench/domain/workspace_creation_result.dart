import 'package:alera/src/features/workbench/domain/workspace.dart';

class const WorkspaceCreationResult({
  required final Workspace workspace,
  required final WorktreeSetupReport setupReport,
  final String? parentLinkError,
  this.deferredSetupCommand,
}) {
  /// Single line to run in a terminal tab named "Setup" instead of having the
  /// host run the worktree setup inline. Null when the setup already ran, which
  /// is what a host without deferral support always reports.
  final String? deferredSetupCommand;

  bool get hasSetupWarnings => setupReport.hasFailures;

  bool get hasParentLinkError => parentLinkError != null;
}

class const WorktreeSetupReport({
  final List<WorktreeSetupStepReport> steps = const <WorktreeSetupStepReport>[],
}) {
  bool get hasFailures => steps.any((step) => !step.succeeded);

  bool get isEmpty => steps.isEmpty;

  String get summary {
    if (steps.isEmpty) {
      return 'No setup actions configured';
    }
    final failures = steps.where((step) => !step.succeeded).length;
    if (failures == 0) {
      return 'Setup completed';
    }
    return '$failures setup action${failures == 1 ? '' : 's'} failed';
  }

  static const empty = WorktreeSetupReport();
}

enum WorktreeSetupStepKind { copy, command, config }

class const WorktreeSetupStepReport({
  required final WorktreeSetupStepKind kind,
  required final String label,
  required final bool succeeded,
  final String? message,
  final int? exitCode,
  final String? stdoutTail,
  final String? stderrTail,
});
