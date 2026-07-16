import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

HostedReview _review(int number, {DateTime? createdAt}) => HostedReview(
  provider: GitHostingProvider.github,
  number: number,
  title: 'feat: $number',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/$number',
  headBranch: 'feature',
  createdAt: createdAt,
);

const _scope = WorkspacePullRequestScope(
  workspaceId: 'w1',
  repoPath: '/repo',
  branch: 'feature',
);

ProviderContainer _container({
  required FakeForgeProvider forge,
  required FakeLinkedReviewRepository repo,
}) {
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
      linkedReviewRepositoryProvider.overrideWithValue(repo),
    ],
  );
  container.listen(workspacePullRequestControllerProvider(_scope), (_, _) {});
  container
      .read(workspacePullRequestControllerProvider(_scope).notifier)
      .attachPanel();
  return container;
}

void main() {
  test('unlink dismisses and suppresses auto-detection', () async {
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final repo = FakeLinkedReviewRepository();
    final container = _container(forge: forge, repo: repo);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    await controller.unlink();

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.dismissed, isTrue);
    expect(state.review, isNull);
    expect(state.suggestedReview?.number, 123);
    expect(repo.store['w1']!.dismissed, isTrue);
    expect(repo.store['w1']!.provider, GitHostingProvider.github);
    expect(repo.store['w1']!.number, 123);
    expect(repo.store['w1']!.hasDismissedReview, isTrue);
  });

  test(
    'auto-detects a different PR after unlinking the previous one',
    () async {
      final forge = FakeForgeProvider()..branchReview = _review(123);
      final repo = FakeLinkedReviewRepository();
      final container = _container(forge: forge, repo: repo);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      final controller = container.read(
        workspacePullRequestControllerProvider(_scope).notifier,
      );
      await controller.unlink();

      forge.branchReview = _review(456);
      await controller.refresh();

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.review?.number, 456);
      expect(state.suggestedReview, isNull);
      expect(state.dismissed, isFalse);
      expect(repo.store['w1']?.number, 123);
    },
  );

  test('does not load checks or comments for the ignored PR', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(123)
      ..checks = const <ReviewCheck>[
        ReviewCheck(
          name: 'build',
          status: ReviewCheckStatus.completed,
          conclusion: ReviewCheckConclusion.success,
        ),
      ];
    final repo = FakeLinkedReviewRepository();
    final container = _container(forge: forge, repo: repo);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    expect(forge.checksCalls, 1);
    expect(forge.commentsCalls, 1);

    await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .unlink();

    expect(forge.checksCalls, 1);
    expect(forge.commentsCalls, 1);
  });

  test('linking the ignored PR replaces its dismissal', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(123)
      ..byNumber[123] = _review(123);
    final repo = FakeLinkedReviewRepository();
    final container = _container(forge: forge, repo: repo);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    await controller.unlink();
    await controller.link('#123');

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.review?.number, 123);
    expect(state.linkedManually, isTrue);
    expect(repo.store['w1']?.dismissed, isFalse);
  });

  test('legacy dismissals ignore old PRs but allow newer PRs', () async {
    final dismissalTime = DateTime.utc(2026, 7, 10);
    final forge = FakeForgeProvider()
      ..branchReview = _review(123, createdAt: DateTime.utc(2026, 7, 9));
    final repo = FakeLinkedReviewRepository()
      ..store['w1'] = LinkedReview.dismissal(
        workspaceId: 'w1',
        linkedAt: dismissalTime,
      );
    final container = _container(forge: forge, repo: repo);
    addTearDown(container.dispose);

    final initial = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(initial.review, isNull);
    expect(initial.suggestedReview?.number, 123);

    forge.branchReview = _review(124, createdAt: DateTime.utc(2026, 7, 11));
    await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .refresh();

    final refreshed = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(refreshed.review?.number, 124);
    expect(refreshed.suggestedReview, isNull);
  });
}
