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
