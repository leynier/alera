import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';

class PromptWorkspaceBranchChecks({
  required final String? hostId,
  required final GitBackend git,
  required final Future<ProjectBranchCatalog> Function(Project, String?)
  loadHostCatalog,
  required final Iterable<Workspace> Function() workspaces,
}) {
  Future<bool> branchExists(Project project, String branch) async {
    // No host means the project's own: this device, unless the project lives
    // only on a server, where there is no local repository to ask.
    final owner =
        normalizedRemoteHostId(hostId) ??
        (project.isRemoteOnly ? project.primaryHostId : null);
    if (owner == null) return git.branchExists(project.repoPath, branch);
    final catalog = await loadHostCatalog(project, owner);
    return catalog.localBranches.contains(branch);
  }

  Set<String> workspaceBranches(Project project) {
    final owner = normalizedRemoteHostId(hostId) ?? localWorkspaceHostId;
    return workspaces()
        .where(
          (workspace) =>
              workspace.projectId == project.id &&
              workspace.isActive &&
              workspace.hostId == owner,
        )
        .map((workspace) => workspace.branch?.trim() ?? '')
        .where((branch) => branch.isNotEmpty)
        .toSet();
  }
}
