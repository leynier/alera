/// One local workspace that can contribute a branch to a pull-request stack.
class const ReviewStackWorkspaceCandidate({
  required final String workspaceId,
  required final String name,
  required final String repoPath,
  required final String branch,
  required final bool current,
  final String? sourceBranch,
  final String? parentWorkspaceId,
});

/// User-confirmed details for one stack layer. The title, body, and draft flag
/// are used only when the branch does not already have an open pull request.
class const ReviewStackWorkspaceLayerInput({
  required final String workspaceId,
  required final String repoPath,
  required final String branch,
  required final String title,
  required final bool draft,
  final String? body,
});

class const ReviewStackWorkspaceRequest({
  required final String baseBranch,
  required final List<ReviewStackWorkspaceLayerInput> layers,
});
