import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// Classification of `az` CLI failures into typed domain results, kept apart
/// from the command construction in `AzureDevOpsForgeProvider`.
bool azLooksLikeMissingCli(ProcessRunOutput result) {
  if (result.exitCode == 127) {
    return true;
  }
  final combined = '${result.stdout} ${result.stderr}'.toLowerCase();
  return combined.contains('command not found') ||
      combined.contains('is not recognized') ||
      combined.contains('no such file') ||
      combined.contains("'repos' is misspelled") ||
      combined.contains('az extension add');
}

bool _looksUnauthenticated(String stderr) {
  final lower = stderr.toLowerCase();
  return lower.contains('az login') || lower.contains('not logged in');
}

CreateReviewFailure mapAzureCreateFailure(ProcessRunOutput result) {
  if (azLooksLikeMissingCli(result)) {
    return const CreateReviewFailure(
      code: CreateReviewErrorCode.cliMissing,
      message: 'The az CLI or azure-devops extension is not installed.',
    );
  }
  if (_looksUnauthenticated(result.stderr)) {
    return const CreateReviewFailure(
      code: CreateReviewErrorCode.notAuthenticated,
      message: 'Run `az login` to authenticate.',
    );
  }
  final stderr = result.stderr.toLowerCase();
  if (stderr.contains('already exists') ||
      stderr.contains('active pull request')) {
    return const CreateReviewFailure(
      code: CreateReviewErrorCode.alreadyExists,
      message: 'A pull request already exists for this branch.',
    );
  }
  return CreateReviewFailure(
    code: CreateReviewErrorCode.unknown,
    message: result.stderr.trim().isEmpty
        ? 'az repos pr create failed.'
        : result.stderr.trim(),
  );
}

UpdateReviewFailure mapAzureUpdateFailure(ProcessRunOutput result) {
  if (azLooksLikeMissingCli(result)) {
    return const UpdateReviewFailure(
      code: UpdateReviewErrorCode.cliMissing,
      message: 'The az CLI or azure-devops extension is not installed.',
    );
  }
  if (_looksUnauthenticated(result.stderr)) {
    return const UpdateReviewFailure(
      code: UpdateReviewErrorCode.notAuthenticated,
      message: 'Run `az login` to authenticate.',
    );
  }
  return UpdateReviewFailure(
    code: UpdateReviewErrorCode.unknown,
    message: result.stderr.trim().isEmpty
        ? 'az repos pr update failed.'
        : result.stderr.trim(),
  );
}
