import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// Classification of `gh` CLI failures into typed domain results, kept apart
/// from the command construction in `GitHubForgeProvider`.
bool ghLooksLikeMissingCli(ProcessRunOutput result) {
  if (result.exitCode != 127) {
    final combined = '${result.stdout} ${result.stderr}'.toLowerCase();
    return combined.contains('command not found') ||
        combined.contains('is not recognized') ||
        combined.contains('no such file');
  }
  return true;
}

bool _looksUnauthenticated(String stderr) {
  final lower = stderr.toLowerCase();
  return lower.contains('not logged') ||
      lower.contains('authentication') ||
      lower.contains('gh auth login');
}

/// User-facing copy when GitHub rejects a merge method that the repository or
/// a ruleset does not allow. Null when [stderr] is some other failure.
String? mapGitHubDisallowedMergeMethodMessage(String stderr) {
  final lower = stderr.toLowerCase();
  if (lower.contains('merge commits are not allowed')) {
    return 'Merge commits are not allowed on this repository. Use squash '
        'and merge or rebase and merge instead.';
  }
  if (lower.contains('squash merges are not allowed') ||
      lower.contains('squash merging is not allowed')) {
    return 'Squash and merge is not allowed on this repository. Choose a '
        'merge method that the repository permits.';
  }
  if (lower.contains('rebase merges are not allowed') ||
      lower.contains('rebase merging is not allowed')) {
    return 'Rebase and merge is not allowed on this repository. Choose a '
        'merge method that the repository permits.';
  }
  if (lower.contains('merge method') &&
      (lower.contains('not allowed') || lower.contains('is disabled'))) {
    return 'That merge method is not allowed on this repository. Choose a '
        'method enabled in the repository settings or branch ruleset.';
  }
  return null;
}

CreateReviewFailure mapGitHubCreateFailure(ProcessRunOutput result) {
  if (ghLooksLikeMissingCli(result)) {
    return const CreateReviewFailure(
      code: .cliMissing,
      message: 'The gh CLI was not found on PATH.',
    );
  }
  if (_looksUnauthenticated(result.stderr)) {
    return const CreateReviewFailure(
      code: .notAuthenticated,
      message: 'Run `gh auth login` to authenticate.',
    );
  }
  final stderr = result.stderr.toLowerCase();
  if (stderr.contains('already exists') ||
      stderr.contains('a pull request for branch')) {
    return const CreateReviewFailure(
      code: .alreadyExists,
      message: 'A pull request already exists for this branch.',
    );
  }
  return CreateReviewFailure(
    code: .unknown,
    message: result.stderr.trim().isEmpty
        ? 'gh pr create failed.'
        : result.stderr.trim(),
  );
}

UpdateReviewFailure mapGitHubUpdateFailure(ProcessRunOutput result) {
  if (ghLooksLikeMissingCli(result)) {
    return const UpdateReviewFailure(
      code: .cliMissing,
      message: 'The gh CLI was not found on PATH.',
    );
  }
  if (_looksUnauthenticated(result.stderr)) {
    return const UpdateReviewFailure(
      code: .notAuthenticated,
      message: 'Run `gh auth login` to authenticate.',
    );
  }
  return UpdateReviewFailure(
    code: .unknown,
    message: result.stderr.trim().isEmpty
        ? 'gh pr edit failed.'
        : result.stderr.trim(),
  );
}
