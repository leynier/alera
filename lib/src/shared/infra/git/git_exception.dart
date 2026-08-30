/// Domain-level git failures raised by [GitBackend]. This sealed hierarchy keeps
/// callers (and tests) free of the flutter_rust_bridge generated types: the
/// `RustGitBackend` translates the native `GitError` into one of these.
sealed class const GitException(this.context) implements Exception {
  /// The relevant detail for this failure (an offending path, branch name, or
  /// the underlying git message).
  final String context;

  @override
  String toString() => '$runtimeType: $context';
}

/// The path is not a git repository.
class const NotARepositoryException(super.context) extends GitException;

/// The operating system denied access to the path (e.g. macOS sandbox).
class const AccessDeniedException(super.context) extends GitException;

/// The requested branch does not exist.
class const BranchNotFoundException(super.context) extends GitException;

/// A branch with the requested name already exists.
class const BranchAlreadyExistsException(super.context) extends GitException;

/// The branch name is not a valid git ref name.
class const InvalidBranchNameException(super.context) extends GitException;

/// A worktree already exists at the requested location.
class const WorktreeAlreadyExistsException(super.context) extends GitException;

/// No worktree was found at the requested location.
class const WorktreeNotFoundException(super.context) extends GitException;

/// `git clone` failed.
class const CloneFailedException(super.context) extends GitException;

/// A delegated `git` CLI invocation failed.
class const GitCliException(super.context) extends GitException;

/// The current checkout is detached and the requested operation needs a branch.
class const DetachedHeadException(super.context) extends GitException;

/// The current branch does not have an upstream configured.
class const NoUpstreamException(super.context) extends GitException;

/// The requested remote does not exist.
class const RemoteNotFoundException(super.context) extends GitException;

/// There is nothing staged or stashed for the requested operation.
class const NothingToCommitException(super.context) extends GitException;

/// The requested workspace-scoped operation would affect hidden repo changes.
class const WorkspaceScopeException(super.context) extends GitException;

/// Git user.name or user.email is missing for commit authoring.
class const MissingIdentityException(super.context) extends GitException;

/// The repository has unresolved merge conflicts.
class const GitConflictException(super.context) extends GitException;

/// An unclassified libgit2 failure.
class const GitInternalException(super.context) extends GitException;
