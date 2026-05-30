/// Domain-level git failures raised by [GitBackend]. This sealed hierarchy keeps
/// callers (and tests) free of the flutter_rust_bridge generated types: the
/// `RustGitBackend` translates the native `GitError` into one of these.
sealed class GitException implements Exception {
  const GitException(this.context);

  /// The relevant detail for this failure (an offending path, branch name, or
  /// the underlying git message).
  final String context;

  @override
  String toString() => '$runtimeType: $context';
}

/// The path is not a git repository.
class NotARepositoryException extends GitException {
  const NotARepositoryException(super.context);
}

/// The operating system denied access to the path (e.g. macOS sandbox).
class AccessDeniedException extends GitException {
  const AccessDeniedException(super.context);
}

/// The requested branch does not exist.
class BranchNotFoundException extends GitException {
  const BranchNotFoundException(super.context);
}

/// A branch with the requested name already exists.
class BranchAlreadyExistsException extends GitException {
  const BranchAlreadyExistsException(super.context);
}

/// The branch name is not a valid git ref name.
class InvalidBranchNameException extends GitException {
  const InvalidBranchNameException(super.context);
}

/// A worktree already exists at the requested location.
class WorktreeAlreadyExistsException extends GitException {
  const WorktreeAlreadyExistsException(super.context);
}

/// No worktree was found at the requested location.
class WorktreeNotFoundException extends GitException {
  const WorktreeNotFoundException(super.context);
}

/// `git clone` failed.
class CloneFailedException extends GitException {
  const CloneFailedException(super.context);
}

/// A delegated `git` CLI invocation failed.
class GitCliException extends GitException {
  const GitCliException(super.context);
}

/// An unclassified libgit2 failure.
class GitInternalException extends GitException {
  const GitInternalException(super.context);
}
