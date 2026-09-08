part of 'workspace_git_diff_panel.dart';

String _messageFor(Object? error) {
  if (error is NotARepositoryException) {
    return 'This workspace is not a Git repository.';
  }
  if (error is DetachedHeadException) {
    return 'Cannot push from detached HEAD.';
  }
  if (error is BranchAlreadyExistsException) {
    return 'A branch named "${error.context}" already exists.';
  }
  if (error is BranchNotFoundException) {
    return 'Branch "${error.context}" was not found.';
  }
  if (error is InvalidBranchNameException) {
    return 'Enter a valid branch name.';
  }
  if (error is RemoteNotFoundException) {
    return 'Remote origin was not found.';
  }
  if (error is NothingToCommitException) {
    return 'Nothing to commit.';
  }
  if (error is GitConflictException) {
    final context = error.context.trim();
    return context.isEmpty ? 'Resolve conflicts before continuing.' : context;
  }
  if (error is AiAssistException) {
    return error.message;
  }
  if (error is GitException && error.context.trim().isNotEmpty) {
    return error.context;
  }
  return 'Git operation failed.';
}

typedef OpenGitDiffTabCallback = Future<void> Function({
  String? relativePath,
  GitChangeArea? area,
  String? gitDiffRoot,
  required WorkspaceGitDiffScope scope,
  bool preview,
});

typedef OpenGitCommitDiffTabCallback = Future<void> Function({
  String? relativePath,
  String? oldPath,
  required WorkspaceGitDiffScope scope,
  String? gitDiffRoot,
  required String commitOid,
  String? parentOid,
  required String compareRef,
  String? subject,
  String? message,
  bool preview,
});
