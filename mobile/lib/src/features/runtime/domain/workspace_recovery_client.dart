import 'workspace_creation_result.dart';
import 'workspace_relocation_recovery.dart';
import 'workspace_summary.dart';

abstract interface class WorkspaceRecoveryClient {
  bool get supportsWorkspaceRecovery;
  Future<WorkspaceRelocationRecoverySnapshot> inspectWorkspaceRecovery(
    WorkspaceSummary workspace,
  );
  Future<WorkspaceCreationResult> resumeWorkspaceRecovery(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry, {
    required bool sharedImpactConfirmed,
  });
  Future<void> runWorkspaceRecoverySetup(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry,
  );
  Future<void> cancelWorkspaceRecoverySetup(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry,
  );
  Future<void> recoverWorkspaceSetupOutcome(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry,
  );
}
