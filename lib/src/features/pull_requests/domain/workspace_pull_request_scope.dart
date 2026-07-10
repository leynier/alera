import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';

/// Immutable inputs the pull-request controller is keyed by. The feature-level
/// panel builds this from the active [Workspace] and the project's resolved
/// hosting-provider override, so the controller itself stays free of workspace
/// and project lookups. Value equality lets Riverpod cache one controller per
/// distinct scope.
class WorkspacePullRequestScope {
  const WorkspacePullRequestScope({
    required this.workspaceId,
    required this.repoPath,
    this.branch,
    this.providerOverride,
  });

  /// Identifies the workspace for persisting the linked review.
  final String workspaceId;

  /// The checkout directory used as the working directory for git and CLI calls.
  final String repoPath;

  /// Branch hint (a git-repository workspace's branch). Null for Folder
  /// workspaces, where the controller resolves the branch from [repoPath].
  final String? branch;

  /// Project-level provider override; null means auto-detect from the remote.
  final GitHostingProvider? providerOverride;

  @override
  bool operator ==(Object other) =>
      other is WorkspacePullRequestScope &&
      other.workspaceId == workspaceId &&
      other.repoPath == repoPath &&
      other.branch == branch &&
      other.providerOverride == providerOverride;

  @override
  int get hashCode =>
      Object.hash(workspaceId, repoPath, branch, providerOverride);
}
