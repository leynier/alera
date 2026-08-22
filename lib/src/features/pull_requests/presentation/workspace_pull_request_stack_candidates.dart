import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

List<ReviewStackWorkspaceCandidate> buildReviewStackWorkspaceCandidates({
  required Iterable<Workspace> workspaces,
  required String currentWorkspaceId,
  required String currentRepoPath,
}) {
  return <ReviewStackWorkspaceCandidate>[
    for (final workspace in workspaces)
      if (workspace.isActive &&
          !workspace.isMain &&
          workspace.branch?.trim().isNotEmpty == true)
        ReviewStackWorkspaceCandidate(
          workspaceId: workspace.id,
          name: workspace.name,
          repoPath: workspace.id == currentWorkspaceId
              ? currentRepoPath
              : workspace.path,
          branch: workspace.branch!.trim(),
          current: workspace.id == currentWorkspaceId,
          sourceBranch: workspace.sourceBranch,
          parentWorkspaceId: workspace.parentWorkspaceId,
        ),
  ];
}

List<ReviewStackWorkspaceCandidate> applyLiveReviewStackWorkspaceBranch({
  required List<ReviewStackWorkspaceCandidate> candidates,
  required String? branch,
}) {
  final liveBranch = branch?.trim();
  if (liveBranch == null || liveBranch.isEmpty) {
    return candidates;
  }
  return <ReviewStackWorkspaceCandidate>[
    for (final candidate in candidates)
      candidate.current
          ? ReviewStackWorkspaceCandidate(
              workspaceId: candidate.workspaceId,
              name: candidate.name,
              repoPath: candidate.repoPath,
              branch: liveBranch,
              current: true,
              sourceBranch: candidate.sourceBranch,
              parentWorkspaceId: candidate.parentWorkspaceId,
            )
          : candidate,
  ];
}
