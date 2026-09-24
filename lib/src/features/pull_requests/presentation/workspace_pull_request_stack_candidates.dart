import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

List<ReviewStackWorkspaceCandidate> buildReviewStackWorkspaceCandidates({
  required Iterable<Workspace> workspaces,
  required String currentWorkspaceId,
  required String currentRepoPath,
}) {
  return <ReviewStackWorkspaceCandidate>[
    for (final workspace in workspaces)
      if (workspace.isActive && workspace.branch?.trim().isNotEmpty == true)
        ReviewStackWorkspaceCandidate(
          workspaceId: workspace.id,
          name: workspace.name,
          repoPath: workspace.id == currentWorkspaceId
              ? currentRepoPath
              : workspace.path,
          branch: workspace.branch!.trim(),
          current: workspace.id == currentWorkspaceId,
          repositoryId: '${workspace.hostId}:${workspace.projectId}',
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
    return _uniqueRepositoryBranches(candidates);
  }
  final currentCandidate = candidates
      .where((candidate) => candidate.current)
      .firstOrNull;
  return _uniqueRepositoryBranches(<ReviewStackWorkspaceCandidate>[
    for (final candidate in candidates)
      candidate.current ||
              (candidate.repoPath == currentCandidate?.repoPath &&
                  candidate.repositoryId == currentCandidate?.repositoryId)
          ? ReviewStackWorkspaceCandidate(
              workspaceId: candidate.workspaceId,
              name: candidate.name,
              repoPath: candidate.repoPath,
              branch: liveBranch,
              current: candidate.current,
              repositoryId: candidate.repositoryId,
              sourceBranch: candidate.sourceBranch,
              parentWorkspaceId: candidate.parentWorkspaceId,
            )
          : candidate,
  ]);
}

List<ReviewStackWorkspaceCandidate> _uniqueRepositoryBranches(
  List<ReviewStackWorkspaceCandidate> candidates,
) {
  final byBranch = <(String, String), ReviewStackWorkspaceCandidate>{};
  for (final candidate in candidates) {
    final key = (
      candidate.repositoryId ?? candidate.repoPath,
      candidate.branch,
    );
    if (!byBranch.containsKey(key) || candidate.current) {
      byBranch[key] = candidate;
    }
  }
  return byBranch.values.toList(growable: false);
}
