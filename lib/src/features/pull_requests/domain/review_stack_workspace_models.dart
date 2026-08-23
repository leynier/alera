/// One local workspace that can contribute a branch to a pull-request stack.
class ReviewStackWorkspaceCandidate {
  const ReviewStackWorkspaceCandidate({
    required this.workspaceId,
    required this.name,
    required this.repoPath,
    required this.branch,
    required this.current,
    this.sourceBranch,
    this.parentWorkspaceId,
  });

  final String workspaceId;
  final String name;
  final String repoPath;
  final String branch;
  final bool current;
  final String? sourceBranch;
  final String? parentWorkspaceId;
}

/// User-confirmed details for one stack layer. The title, body, and draft flag
/// are used only when the branch does not already have an open pull request.
class ReviewStackWorkspaceLayerInput {
  const ReviewStackWorkspaceLayerInput({
    required this.workspaceId,
    required this.repoPath,
    required this.branch,
    required this.title,
    required this.draft,
    this.body,
  });

  final String workspaceId;
  final String repoPath;
  final String branch;
  final String title;
  final String? body;
  final bool draft;
}

class ReviewStackWorkspaceRequest {
  const ReviewStackWorkspaceRequest({
    required this.baseBranch,
    required this.layers,
  });

  final String baseBranch;
  final List<ReviewStackWorkspaceLayerInput> layers;
}
