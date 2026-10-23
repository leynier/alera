import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/host_routed_git_backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<String?> runWorkspaceGitSubmissionJob(
  ProviderContainer container,
  Workspace original,
  WorkspacePullRequestScope scope,
  WorkspaceGitSubmission submission, {
  void Function(String phase)? onPhase,
  void Function(String line)? onOutput,
}) async {
  void verifyOwner() {
    final live = container
        .read(workbenchControllerProvider)
        .workspacesByProject
        .values
        .expand((workspaces) => workspaces)
        .where((workspace) => workspace.id == original.id)
        .firstOrNull;
    if (live == null ||
        live.hostId != original.hostId ||
        live.path != original.path) {
      throw StateError(
        'The workspace was removed or moved. Review the remaining action on its current host.',
      );
    }
  }

  verifyOwner();
  final router = container.read(gitBackendProvider);
  final git = router is HostRoutedGitBackend
      ? router.forPath(scope.repoPath)
      : router;
  final provider = workspaceSourceControlControllerProvider(scope.repoPath);
  final subscription = container.listen(provider, (_, _) {});
  try {
    await container.read(provider.future);
    verifyOwner();
    final source = container.read(provider.notifier);
    final pullRequest = container.read(
      workspacePullRequestControllerProvider(scope).notifier,
    );
    await source.runReviewedAction(
      (_) => submission.run(
        git,
        (input) {
          verifyOwner();
          return pullRequest.createReview(input, pushBranch: false);
        },
        onPhase: onPhase,
        onOutput: onOutput,
      ),
    );
    return null;
  } catch (error) {
    return '${submission.completedSummary}${userFacingErrorMessage(error)}';
  } finally {
    subscription.close();
  }
}
