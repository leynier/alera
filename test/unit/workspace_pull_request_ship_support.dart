import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

/// Shared fixtures for the Ship suites (staged-only and stage-all).
const shipTestScope = WorkspacePullRequestScope(
  workspaceId: 'workspace-1',
  repoPath: '/repo',
  branch: 'main',
);

const emptyShipRange = GitRangeContext(
  baseRef: 'refs/remotes/origin/main',
  commits: <GitRangeCommit>[],
  files: <GitRangeFile>[],
  patch: '',
);

const unpushedMainRange = GitRangeContext(
  baseRef: 'refs/remotes/origin/main',
  headOid: 'abc1234',
  headBranch: 'main',
  commits: <GitRangeCommit>[
    GitRangeCommit(
      oid: 'abc1234',
      subject: 'feat: local main commit',
      message: 'feat: local main commit\n\nKeep main matching origin.',
    ),
  ],
  files: <GitRangeFile>[
    GitRangeFile(
      path: 'lib/ship.dart',
      status: .modified,
      added: 4,
      removed: 1,
    ),
  ],
  patch: 'diff --git a/lib/ship.dart b/lib/ship.dart',
);

HostedReview shipTestReview(
  int number, {
  required String headBranch,
  String baseBranch = 'main',
}) => HostedReview(
  provider: .github,
  number: number,
  title: 'feat: shipped changes',
  state: .open,
  url: 'https://github.com/leynier/alera/pull/$number',
  headBranch: headBranch,
  baseBranch: baseBranch,
);

ProviderContainer createShipTestContainer({
  required FakeGitBackend git,
  required FakeForgeProvider forge,
  required FakeLinkedReviewRepository linkedReviews,
  required AiAssistService aiAssist,
}) {
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(git),
      aiAssistServiceProvider.overrideWithValue(aiAssist),
      forgeProviderRegistryProvider.overrideWithValue(
        ForgeProviderRegistry(<ForgeProvider>[forge]),
      ),
      linkedReviewRepositoryProvider.overrideWithValue(linkedReviews),
    ],
  );
  container.listen(
    workspacePullRequestControllerProvider(shipTestScope),
    (_, _) {},
  );
  container
      .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
      .attachPanel();
  return container;
}

class FakeShipAiAssistService implements AiAssistService {
  FakeShipAiAssistService(List<Object> responses)
    : _responses = List<Object>.of(responses);

  final List<Object> _responses;
  final List<AiAssistRequest> requests = <AiAssistRequest>[];

  @override
  Future<AiAssistResult> generate(AiAssistRequest request) async {
    requests.add(request);
    final response = _responses.removeAt(0);
    if (response is Exception) {
      throw response;
    }
    return response as AiAssistResult;
  }

  @override
  void cancel(String workspacePath, AiAssistOperation operation) {}
}
