import 'package:alera/src/features/workbench/domain/workspace.dart';

class WorkspaceCreationResult {
  const WorkspaceCreationResult({
    required this.workspace,
    required this.setupReport,
    this.parentLinkError,
    this.deferredSetupCommand,
  });

  final Workspace workspace;
  final WorktreeSetupReport setupReport;
  final String? parentLinkError;

  /// Single line to run in a terminal tab named "Setup" instead of having the
  /// host run the worktree setup inline. Null when the setup already ran, which
  /// is what a host without deferral support always reports.
  final String? deferredSetupCommand;

  bool get hasSetupWarnings => setupReport.hasFailures;

  bool get hasParentLinkError => parentLinkError != null;
}

class WorktreeSetupReport {
  const WorktreeSetupReport({this.steps = const <WorktreeSetupStepReport>[]});

  final List<WorktreeSetupStepReport> steps;

  bool get hasFailures => steps.any((step) => !step.succeeded);

  bool get isEmpty => steps.isEmpty;

  String get summary {
    if (steps.isEmpty) {
      return 'No Setup Actions Configured';
    }
    final failures = steps.where((step) => !step.succeeded).length;
    if (failures == 0) {
      return 'Setup Completed';
    }
    return '$failures Setup Action${failures == 1 ? '' : 's'} Failed';
  }

  static const empty = WorktreeSetupReport();
}

enum WorktreeSetupStepKind { copy, command, config }

class WorktreeSetupStepReport {
  const WorktreeSetupStepReport({
    required this.kind,
    required this.label,
    required this.succeeded,
    this.message,
    this.exitCode,
    this.stdoutTail,
    this.stderrTail,
  });

  final WorktreeSetupStepKind kind;
  final String label;
  final bool succeeded;
  final String? message;
  final int? exitCode;
  final String? stdoutTail;
  final String? stderrTail;
}
