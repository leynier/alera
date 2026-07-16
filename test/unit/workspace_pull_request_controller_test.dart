import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

HostedReview _review(
  int number, {
  HostedReviewState state = HostedReviewState.open,
  DateTime? createdAt,
}) => HostedReview(
  provider: GitHostingProvider.github,
  number: number,
  title: 'feat: $number',
  state: state,
  url: 'https://github.com/leynier/alera/pull/$number',
  headBranch: 'feature',
  createdAt: createdAt,
);

const _scope = WorkspacePullRequestScope(
  workspaceId: 'w1',
  repoPath: '/repo',
  branch: 'feature',
);

// A Folder workspace has no branch hint; the controller must resolve it from
// the controlled repo via GitBackend.currentBranch.
const _folderScope = WorkspacePullRequestScope(
  workspaceId: 'w1',
  repoPath: '/repo/sub',
);

ProviderContainer _container({
  required FakeForgeProvider forge,
  required FakeLinkedReviewRepository repo,
  FakeGitBackend? git,
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
  test('auto-detects the review for the branch on open', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(123)
      ..checks = <ReviewCheck>[
        const ReviewCheck(
          name: 'build',
          status: ReviewCheckStatus.completed,
          conclusion: ReviewCheckConclusion.success,
        ),
      ];
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(state.review?.number, 123);
    expect(state.linkedManually, isFalse);
    expect(state.checks, hasLength(1));
    expect(state.checksRollup, ReviewChecksRollup.success);
  });

  test('reports not-authenticated without showing a review', () async {
    final forge = FakeForgeProvider()
      ..auth = ForgeAuthStatus.notAuthenticated
      ..branchReview = _review(123);
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(state.authStatus, ForgeAuthStatus.notAuthenticated);
    expect(state.review, isNull);
  });

  test('link persists the review and displays it', () async {
    final forge = FakeForgeProvider()..byNumber[456] = _review(456);
    final repo = FakeLinkedReviewRepository();
    final container = _container(forge: forge, repo: repo);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    await controller.link('#456');

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.review?.number, 456);
    expect(state.linkedManually, isTrue);
    expect(repo.store['w1']!.number, 456);
  });

  test('link reports an error for an unknown PR', () async {
    final forge = FakeForgeProvider();
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    await controller.link('#999');

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.errorMessage, contains('999'));
    expect(state.review, isNull);
  });

  test('createReview pushes, creates, and links the result', () async {
    final backend = FakeGitBackend()
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final forge = FakeForgeProvider()
      ..createResult = CreateReviewSuccess(_review(789))
      ..byNumber[789] = _review(789);
    final repo = FakeLinkedReviewRepository();
    final container = _container(forge: forge, repo: repo, git: backend);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    final result = await controller.createReview(
      const CreateReviewInput(
        provider: GitHostingProvider.github,
        title: 'feat: 789',
        baseBranch: 'main',
        headBranch: 'feature',
      ),
    );

    expect(result, isA<CreateReviewSuccess>());
    expect(forge.createCalls, 1);
    expect(backend.calls.any((c) => c.method == 'push'), isTrue);
    expect(repo.store['w1']!.number, 789);
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.review?.number, 789);
  });

  test(
    'resolves the branch from the repo when scope has no branch hint',
    () async {
      final backend = FakeGitBackend()
        ..headBranch = 'feature'
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        };
      final forge = FakeForgeProvider()..branchReview = _review(321);
      final container = _container(
        forge: forge,
        repo: FakeLinkedReviewRepository(),
        git: backend,
      );
      addTearDown(container.dispose);

      final state = await container.read(
        workspacePullRequestControllerProvider(_folderScope).future,
      );
      expect(state.currentBranch, 'feature');
      expect(state.review?.number, 321);
    },
  );

  test('does not auto-detect when the controlled repo is detached', () async {
    final backend = FakeGitBackend()
      ..headBranch = 'HEAD'
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final forge = FakeForgeProvider()..branchReview = _review(321);
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
      git: backend,
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_folderScope).future,
    );
    expect(state.currentBranch, isNull);
    expect(state.review, isNull);
  });

  test('loads normalized base branches and suggests main by default', () async {
    final backend = FakeGitBackend()
      ..sourceBranches = <String>['feature', 'origin/main', 'main', 'develop']
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final forge = FakeForgeProvider();
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
      git: backend,
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(state.baseBranches, <String>['develop', 'feature', 'main']);
    expect(state.suggestedBaseBranch, 'main');
  });

  test('updateReview applies the edit and reloads the new title', () async {
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    final updated = HostedReview(
      provider: GitHostingProvider.github,
      number: 123,
      title: 'feat: renamed',
      state: HostedReviewState.open,
      url: 'https://github.com/leynier/alera/pull/123',
      headBranch: 'feature',
      baseBranch: 'develop',
    );
    forge.updateResult = UpdateReviewSuccess(updated);

    final result = await controller.updateReview(
      const UpdateReviewInput(title: 'feat: renamed', baseBranch: 'develop'),
    );

    expect(result, isA<UpdateReviewSuccess>());
    expect(forge.lastUpdateInput?.title, 'feat: renamed');
    expect(forge.lastUpdateInput?.baseBranch, 'develop');
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.review?.title, 'feat: renamed');
    expect(state.review?.baseBranch, 'develop');
    expect(state.errorMessage, isNull);
  });

  test('updateReview failure surfaces the message and keeps the PR', () async {
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    forge.updateResult = const UpdateReviewFailure(
      code: UpdateReviewErrorCode.unknown,
      message: 'permission denied',
    );

    final result = await controller.updateReview(
      const UpdateReviewInput(title: 'feat: renamed'),
    );

    expect(result, isA<UpdateReviewFailure>());
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.errorMessage, 'permission denied');
    expect(state.review?.number, 123);
  });

  test('updateReview is blocked without a linked review', () async {
    final forge = FakeForgeProvider();
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );

    final result = await controller.updateReview(
      const UpdateReviewInput(title: 't'),
    );
    expect(result, isA<UpdateReviewFailure>());
    expect((result as UpdateReviewFailure).code, UpdateReviewErrorCode.blocked);
    expect(forge.updateCalls, 0);
  });

  test(
    'merge keeps an auto-detected PR linked and shows its merged state',
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

      await controller.mergeReview(ReviewMergeMethod.squash);

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(forge.lastMergeMethod, ReviewMergeMethod.squash);
      expect(state.review?.state, HostedReviewState.merged);
      expect(state.linkedManually, isTrue);
      expect(repo.store['w1']?.number, 123);
    },
  );

  test('close keeps the terminal closed state visible', () async {
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final repo = FakeLinkedReviewRepository();
    final container = _container(forge: forge, repo: repo);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );

    await controller.closeReview();

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(forge.closeCalls, 1);
    expect(state.review?.state, HostedReviewState.closed);
    expect(state.linkedManually, isTrue);
  });

  test('blocks a merge method that the provider does not support', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(123)
      ..mergeMethods = const <ReviewMergeMethod>[ReviewMergeMethod.mergeCommit];
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );

    await controller.mergeReview(ReviewMergeMethod.rebase);

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(forge.mergeCalls, 0);
    expect(state.errorMessage, 'This Pull Request Cannot Be Merged.');
    expect(state.review?.state, HostedReviewState.open);
  });

  test('loadCheckDetails queries the linked review number', () async {
    const check = ReviewCheck(
      name: 'build',
      status: ReviewCheckStatus.inProgress,
      conclusion: ReviewCheckConclusion.pending,
    );
    final forge = FakeForgeProvider()
      ..branchReview = _review(123)
      ..checks = <ReviewCheck>[check]
      ..details = const ReviewCheckDetails(workflow: 'CI');
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );

    final details = await controller.loadCheckDetails(check);
    expect(details?.workflow, 'CI');
    expect(forge.lastDetailsNumber, 123);
    expect(forge.lastDetailsCheck?.name, 'build');
  });

  test('prefers scope sourceBranch as suggested base', () async {
    const scope = WorkspacePullRequestScope(
      workspaceId: 'w1',
      repoPath: '/repo',
      branch: 'feature',
      sourceBranch: 'origin/develop',
    );
    final backend = FakeGitBackend()
      ..sourceBranches = <String>['main', 'develop', 'feature']
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final forge = FakeForgeProvider();
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
      git: backend,
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(scope).future,
    );
    expect(state.suggestedBaseBranch, 'develop');
  });
}
