import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

const _scope = WorkspacePullRequestScope(
  workspaceId: 'w1',
  repoPath: '/repo',
  branch: 'feature',
);

HostedReview _review({HostedReviewState state = HostedReviewState.open}) {
  return HostedReview(
    provider: GitHostingProvider.github,
    number: 123,
    title: 'feat: draft status',
    state: state,
    url: 'https://github.com/leynier/alera/pull/123',
    headBranch: 'feature',
  );
}

ProviderContainer _container(FakeForgeProvider forge) {
  final backend = FakeGitBackend()
    ..remotesByName = <String, String?>{
      'origin': 'https://github.com/leynier/alera.git',
    };
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(backend),
      forgeProviderRegistryProvider.overrideWithValue(
        ForgeProviderRegistry(<ForgeProvider>[forge]),
      ),
      linkedReviewRepositoryProvider.overrideWithValue(
        FakeLinkedReviewRepository(),
      ),
    ],
  );
  container.listen(workspacePullRequestControllerProvider(_scope), (_, _) {});
  container
      .read(workspacePullRequestControllerProvider(_scope).notifier)
      .attachPanel();
  return container;
}

void main() {
  test('marks a draft pull request ready for review', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(state: HostedReviewState.draft);
    final container = _container(forge);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );

    await controller.setReviewDraft(false);

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(forge.lastDraftStatus, isFalse);
    expect(state.review?.state, HostedReviewState.open);
  });

  test('converts an open pull request to draft', () async {
    final forge = FakeForgeProvider()..branchReview = _review();
    final container = _container(forge);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );

    await controller.setReviewDraft(true);

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(forge.lastDraftStatus, isTrue);
    expect(state.review?.state, HostedReviewState.draft);
  });

  test(
    'blocks draft conversion when the provider does not support it',
    () async {
      final forge = FakeForgeProvider()
        ..branchReview = _review()
        ..canChangeDraftStatus = false;
      final container = _container(forge);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      final controller = container.read(
        workspacePullRequestControllerProvider(_scope).notifier,
      );

      await controller.setReviewDraft(true);

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(forge.draftStatusCalls, 0);
      expect(
        state.errorMessage,
        'This Pull Request Draft Status Cannot Be Changed.',
      );
      expect(state.review?.state, HostedReviewState.open);
    },
  );
}
