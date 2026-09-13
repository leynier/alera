import 'workspace_creation_result.dart';
import 'workspace_summary.dart';

abstract interface class WorkspaceRelocationClient {
  bool get supportsWorkspaceRelocation;

  Future<WorkspaceCreationResult> handOffWorkspace({
    required String workspaceId,
    required String relocationId,
    required String branch,
    required bool moveChanges,
    required bool sharedImpactConfirmed,
    String? replacementBranch,
  });

  Future<WorkspaceSummary> handOnWorkspace({
    required String workspaceId,
    required String relocationId,
    required bool sharedImpactConfirmed,
  });
}
