import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

HostedReview _review(int number, {String headBranch = 'feature'}) =>
    HostedReview(
      provider: .github,
      number: number,
      title: 'feat: $number',
      state: .open,
      url: 'https://github.com/leynier/alera/pull/$number',
      headBranch: headBranch,
    );

const _scope = WorkspacePullRequestScope(
  workspaceId: 'w1',
  repoPath: '/repo',
  branch: 'feature',
);

/// Fails the first [find] to simulate a broken initial load.
class _ThrowingLinkedReviewRepository extends FakeLinkedReviewRepository {
  int findCalls = 0;

  @override
  Future<LinkedReview?> find(String workspaceId) async {
    findCalls++;
    if (findCalls == 1) {
      throw StateError('linked review storage unavailable');
    }
    return super.find(workspaceId);
  }
}

ProviderContainer _container({
  required FakeForgeProvider forge,
  FakeGitBackend? git,
  FakeLinkedReviewRepository? linkedReviews,
  bool attach = true,
}) {
  final backend =
      git ??
      (FakeGitBackend()
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        });
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(backend),
      forgeProviderRegistryProvider.overrideWithValue(
        ForgeProviderRegistry(<ForgeProvider>[forge]),
      ),
      linkedReviewRepositoryProvider.overrideWithValue(
        linkedReviews ?? FakeLinkedReviewRepository(),
      ),
    ],
  );
  container.listen(workspacePullRequestControllerProvider(_scope), (_, _) {});
  if (attach) {
    container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .attachPanel();
  }
  return container;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) {
      return;
    }
    await tester.pump();
  }
  fail('Condition was not reached after pumping asynchronous work.');
}

void main() {
  test(
    'detects the review on the live branch over a stale scope hint',
    () async {
      // The scope records the branch from workspace creation, but the agent
      // switched the worktree to another branch and opened the PR from it.
      final backend = FakeGitBackend()
        ..headBranch = 'agent-branch'
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        };
      final forge = FakeForgeProvider()
        ..branchReview = _review(123, headBranch: 'agent-branch');
      final container = _container(forge: forge, git: backend);
      addTearDown(container.dispose);

      final state = await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      expect(state.currentBranch, 'agent-branch');
      expect(forge.lastBranchQuery, 'agent-branch');
      expect(state.review?.number, 123);
    },
  );

  test('falls back to the scope hint when the repo is detached', () async {
    final backend = FakeGitBackend()
      ..headBranch = 'HEAD'
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final container = _container(forge: forge, git: backend);
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(state.currentBranch, 'feature');
    expect(forge.lastBranchQuery, 'feature');
  });

  testWidgets('keeps polling while not authenticated and picks up sign-in', (
    tester,
  ) async {
    final forge = FakeForgeProvider()..auth = ForgeAuthStatus.notAuthenticated;
    final container = _container(forge: forge);
    addTearDown(container.dispose);
    final provider = workspacePullRequestControllerProvider(_scope);

    await _pumpUntil(tester, () => container.read(provider).hasValue);
    expect(
      container.read(provider).value?.authStatus,
      ForgeAuthStatus.notAuthenticated,
    );

    forge
      ..auth = ForgeAuthStatus.authenticated
      ..branchReview = _review(321);
    await tester.pump(const Duration(seconds: 121));
    await _pumpUntil(
      tester,
      () => container.read(provider).value?.review?.number == 321,
    );

    final state = container.read(provider).value!;
    expect(state.authStatus, ForgeAuthStatus.authenticated);
    expect(state.review?.number, 321);
    container.read(provider.notifier).detachPanel();
    await tester.pump();
  });

  testWidgets('attachPanel recovers after a failed initial load', (
    tester,
  ) async {
    final forge = FakeForgeProvider()..branchReview = _review(55);
    final linkedReviews = _ThrowingLinkedReviewRepository();
    final container = _container(
      forge: forge,
      linkedReviews: linkedReviews,
      attach: false,
    );
    addTearDown(container.dispose);
    final provider = workspacePullRequestControllerProvider(_scope);

    await _pumpUntil(tester, () => container.read(provider).hasError);
    expect(container.read(provider).hasValue, isFalse);

    container.read(provider.notifier).attachPanel();
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpUntil(
      tester,
      () => container.read(provider).value?.review?.number == 55,
    );
    expect(linkedReviews.findCalls, 2);
    container.read(provider.notifier).detachPanel();
    await tester.pump();
  });

  test(
    'a throwing forge createReview clears the action and error state',
    () async {
      final forge = FakeForgeProvider()..branchReview = _review(123);
      final container = _container(forge: forge);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      final controller = container.read(
        workspacePullRequestControllerProvider(_scope).notifier,
      );
      forge.createError = const ForgeRequestFailed('boom');

      final result = await controller.createReview(
        const CreateReviewInput(
          provider: .github,
          title: 'feat: broken',
          baseBranch: 'main',
          headBranch: 'feature',
        ),
      );

      expect(result, isA<CreateReviewFailure>());
      expect((result as CreateReviewFailure).message, 'boom');
      final wedged = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(wedged.isBusy, isFalse);
      expect(wedged.errorMessage, 'boom');

      // The controller must still be able to refresh after the failure.
      forge.createError = null;
      await controller.refresh();
      final refreshed = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(refreshed.review?.number, 123);
      expect(refreshed.errorMessage, isNull);
    },
  );
}
