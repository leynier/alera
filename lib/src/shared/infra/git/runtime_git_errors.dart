part of 'runtime_git_backend.dart';

/// Rebuilds the [GitException] the bridge would have thrown from the typed
/// `gitError` conflict the runtime answers with.
GitException gitExceptionFromRuntime(TerminalHostConflictException error) {
  final context = switch (error.details['context']) {
    final String context => context,
    _ => error.message,
  };
  return switch (error.details['kind']) {
    'notARepository' => NotARepositoryException(context),
    'accessDenied' => AccessDeniedException(context),
    'branchNotFound' => BranchNotFoundException(context),
    'branchAlreadyExists' => BranchAlreadyExistsException(context),
    'invalidBranchName' => InvalidBranchNameException(context),
    'worktreeAlreadyExists' => WorktreeAlreadyExistsException(context),
    'worktreeNotFound' => WorktreeNotFoundException(context),
    'cloneFailed' => CloneFailedException(context),
    'gitCli' => GitCliException(context),
    'detachedHead' => DetachedHeadException(context),
    'noUpstream' => NoUpstreamException(context),
    'remoteNotFound' => RemoteNotFoundException(context),
    'nothingToCommit' => NothingToCommitException(context),
    'workspaceScope' => WorkspaceScopeException(context),
    'missingIdentity' => MissingIdentityException(context),
    'conflict' => GitConflictException(context),
    _ => GitInternalException(context),
  };
}
