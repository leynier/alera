import 'package:alera/src/shared/infra/git/git_exception.dart';

/// The sentence the UI shows for a [GitException].
///
/// The wording MUST stay identical to `git_error_message` in
/// `rust/alera-cli/src/terminal_host/server/mobile_source_control_snapshot.rs`,
/// because an older phone shows that runtime text verbatim.
String gitErrorMessage(GitException error) {
  final context = error.context.trim();
  return switch (error) {
    NotARepositoryException() => 'This workspace is not a Git repository.',
    DetachedHeadException() => 'Cannot push from detached HEAD.',
    BranchAlreadyExistsException() =>
      'A branch named "$context" already exists.',
    BranchNotFoundException() => 'Branch "$context" was not found.',
    InvalidBranchNameException() => 'Enter a valid branch name.',
    RemoteNotFoundException() => 'Remote origin was not found.',
    NothingToCommitException() => 'Nothing to commit.',
    GitConflictException() when context.isEmpty =>
      'Resolve conflicts before continuing.',
    _ when context.isEmpty => 'Git operation failed.',
    _ => context,
  };
}
