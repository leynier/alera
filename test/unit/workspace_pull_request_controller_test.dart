import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_git_backend.dart';

HostedReview _review(
  int number, {
  HostedReviewState state = HostedReviewState.open,
}) => HostedReview(
  provider: GitHostingProvider.github,
  number: number,
  title: 'feat: $number',
  state: state,
  url: 'https://github.com/leynier/alera/pull/$number',
  headBranch: 'feature',
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
  required _FakeForge forge,
  required _FakeLinkedReviewRepo repo,
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
  return container;
}

void main() {
  test('auto-detects the review for the branch on open', () async {
    final forge = _FakeForge()
      ..branchReview = _review(123)
      ..checks = <ReviewCheck>[
        const ReviewCheck(
          name: 'build',
          status: ReviewCheckStatus.completed,
          conclusion: ReviewCheckConclusion.success,
        ),
      ];
    final container = _container(forge: forge, repo: _FakeLinkedReviewRepo());
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
    final forge = _FakeForge()
      ..auth = ForgeAuthStatus.notAuthenticated
      ..branchReview = _review(123);
    final container = _container(forge: forge, repo: _FakeLinkedReviewRepo());
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(state.authStatus, ForgeAuthStatus.notAuthenticated);
    expect(state.review, isNull);
  });

  test('link persists the review and displays it', () async {
    final forge = _FakeForge()..byNumber[456] = _review(456);
    final repo = _FakeLinkedReviewRepo();
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
    final forge = _FakeForge();
    final container = _container(forge: forge, repo: _FakeLinkedReviewRepo());
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

  test('unlink dismisses and suppresses auto-detection', () async {
    final forge = _FakeForge()..branchReview = _review(123);
    final repo = _FakeLinkedReviewRepo();
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
    expect(repo.store['w1']!.dismissed, isTrue);
  });

  test('createReview pushes, creates, and links the result', () async {
    final backend = FakeGitBackend()
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final forge = _FakeForge()
      ..createResult = CreateReviewSuccess(_review(789))
      ..byNumber[789] = _review(789);
    final repo = _FakeLinkedReviewRepo();
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
      final forge = _FakeForge()..branchReview = _review(321);
      final container = _container(
        forge: forge,
        repo: _FakeLinkedReviewRepo(),
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
    final forge = _FakeForge()..branchReview = _review(321);
    final container = _container(
      forge: forge,
      repo: _FakeLinkedReviewRepo(),
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
    final forge = _FakeForge();
    final container = _container(
      forge: forge,
      repo: _FakeLinkedReviewRepo(),
      git: backend,
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    expect(state.baseBranches, <String>['develop', 'feature', 'main']);
    expect(state.suggestedBaseBranch, 'main');
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
    final forge = _FakeForge();
    final container = _container(
      forge: forge,
      repo: _FakeLinkedReviewRepo(),
      git: backend,
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(scope).future,
    );
    expect(state.suggestedBaseBranch, 'develop');
  });
}

class _FakeForge implements ForgeProvider {
  ForgeAuthStatus auth = ForgeAuthStatus.authenticated;
  HostedReview? branchReview;
  final Map<int, HostedReview> byNumber = <int, HostedReview>{};
  List<ReviewCheck> checks = <ReviewCheck>[];
  CreateReviewResult createResult = const CreateReviewFailure(
    code: CreateReviewErrorCode.unknown,
    message: 'not set',
  );
  int createCalls = 0;

  @override
  GitHostingProvider get id => GitHostingProvider.github;

  @override
  bool get supportsReviewCreation => true;

  @override
  Future<ForgeAuthStatus> checkAuth({
    required GitRemoteIdentity identity,
  }) async => auth;

  @override
  Future<HostedReview?> getReviewForBranch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String branch,
  }) async => branchReview;

  @override
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async => byNumber[number];

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async => checks;

  @override
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  }) async {
    createCalls++;
    return createResult;
  }
}

class _FakeLinkedReviewRepo implements LinkedReviewRepository {
  final Map<String, LinkedReview> store = <String, LinkedReview>{};

  @override
  Future<LinkedReview?> find(String workspaceId) async => store[workspaceId];

  @override
  Stream<LinkedReview?> watch(String workspaceId) async* {
    yield store[workspaceId];
  }

  @override
  Future<void> save(LinkedReview review) async {
    store[review.workspaceId] = review;
  }

  @override
  Future<void> remove(String workspaceId) async {
    store.remove(workspaceId);
  }
}
