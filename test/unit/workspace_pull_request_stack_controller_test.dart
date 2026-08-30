import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/forge_stack_provider.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

const _scope = WorkspacePullRequestScope(
  workspaceId: 'workspace-1',
  repoPath: '/repo',
  branch: 'feature/two',
);

HostedReview _review(
  int number, {
  required String headBranch,
  required String baseBranch,
  HostedReviewState state = HostedReviewState.open,
}) {
  return HostedReview(
    provider: .github,
    number: number,
    title: 'feat: layer $number',
    state: state,
    url: 'https://github.com/leynier/alera/pull/$number',
    headBranch: headBranch,
    baseBranch: baseBranch,
  );
}

HostedReviewStack _stack({
  required HostedReview first,
  required HostedReview second,
}) {
  return HostedReviewStack(
    number: 700,
    baseBranch: first.baseBranch ?? 'main',
    open: true,
    entries: <HostedReviewStackEntry>[
      HostedReviewStackEntry(review: first, position: 1),
      HostedReviewStackEntry(review: second, position: 2),
    ],
  );
}

ProviderContainer _container({
  required _FakeStackForgeProvider forge,
  FakeLinkedReviewRepository? linkedReviews,
  FakeGitBackend? gitBackend,
}) {
  final git =
      gitBackend ??
      (FakeGitBackend()
        ..headBranch = 'feature/two'
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        });
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(git),
      forgeProviderRegistryProvider.overrideWithValue(
        ForgeProviderRegistry(<ForgeProvider>[forge]),
      ),
      linkedReviewRepositoryProvider.overrideWithValue(
        linkedReviews ?? FakeLinkedReviewRepository(),
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
  test('loads native stack state without changing the linked review', () async {
    final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
    final second = _review(
      42,
      headBranch: 'feature/two',
      baseBranch: 'feature/one',
    );
    final forge = _FakeStackForgeProvider()
      ..branchReview = second
      ..stack = _stack(first: first, second: second);
    forge.byNumber
      ..[41] = first
      ..[42] = second;
    final container = _container(forge: forge);
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );

    expect(state.review?.number, 42);
    expect(state.stackSupported, isTrue);
    expect(state.stack?.number, 700);
    expect(state.stack?.positionForReview(42), 2);
    expect(forge.stackLoadCalls, 1);
  });

  test(
    'creates a stack from existing pull requests in the supplied order',
    () async {
      final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
      final second = _review(
        42,
        headBranch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final linkedReviews = FakeLinkedReviewRepository();
      final forge = _FakeStackForgeProvider()..branchReview = second;
      forge.byNumber
        ..[41] = first
        ..[42] = second;
      final container = _container(forge: forge, linkedReviews: linkedReviews);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .linkReviewStack(const <int>[41, 42]);

      expect(forge.linkedReviewNumbers, <int>[41, 42]);
      expect(forge.linkedStackNumber, isNull);
      expect(forge.linkedBaseBranch, 'main');
      expect(linkedReviews.store[_scope.workspaceId]?.number, 42);
      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.stack?.entries.map((entry) => entry.review.number), <int>[
        41,
        42,
      ]);
    },
  );

  test(
    'merges through the current pull request using the stack provider',
    () async {
      final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
      final second = _review(
        42,
        headBranch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final forge = _FakeStackForgeProvider()
        ..branchReview = second
        ..stack = _stack(first: first, second: second);
      forge.byNumber
        ..[41] = first
        ..[42] = second;
      final container = _container(forge: forge);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .mergeReview(.squash);

      expect(forge.stackMergeCalls, 1);
      expect(forge.lastStackMergeReviewNumber, 42);
      expect(forge.lastStackMergeMethod, ReviewMergeMethod.squash);
      expect(forge.mergeCalls, 0);
    },
  );

  test('rejects a new stack that omits the current pull request', () async {
    final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
    final second = _review(
      42,
      headBranch: 'feature/two',
      baseBranch: 'feature/one',
    );
    final forge = _FakeStackForgeProvider()..branchReview = second;
    forge.byNumber
      ..[41] = first
      ..[42] = second;
    final container = _container(forge: forge);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .linkReviewStack(const <int>[40, 41]);

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.errorMessage, contains('current pull request'));
    expect(forge.linkStackCalls, 0);
  });

  test(
    'rejects a branch that is not descended from the layer below it',
    () async {
      final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
      final second = _review(
        42,
        headBranch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final git = FakeGitBackend()
        ..headBranch = 'feature/two'
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..ancestorResults[('main', 'feature/one')] = true
        ..ancestorResults[('feature/one', 'feature/two')] = false;
      final forge = _FakeStackForgeProvider()..branchReview = second;
      forge.byNumber
        ..[41] = first
        ..[42] = second;
      final container = _container(forge: forge, gitBackend: git);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .linkReviewStack(const <int>[41, 42]);

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.errorMessage, contains('must descend'));
      expect(state.errorMessage, contains('feature/one'));
      expect(forge.linkStackCalls, 0);
      expect(
        git.calls.where((call) => call.method == 'isAncestor'),
        hasLength(2),
      );
    },
  );

  test(
    'fetches once when stack branch refs are not available locally',
    () async {
      final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
      final second = _review(
        42,
        headBranch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final git = FakeGitBackend()
        ..headBranch = 'feature/two'
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..isAncestorError = const BranchNotFoundException('remote ref missing');
      git.onFetch = () => git.isAncestorError = null;
      final forge = _FakeStackForgeProvider()..branchReview = second;
      forge.byNumber
        ..[41] = first
        ..[42] = second;
      final container = _container(forge: forge, gitBackend: git);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .linkReviewStack(const <int>[41, 42]);

      expect(forge.linkStackCalls, 1);
      expect(git.calls.where((call) => call.method == 'fetch'), hasLength(1));
      expect(
        git.calls.where((call) => call.method == 'isAncestor'),
        hasLength(3),
      );
    },
  );

  test(
    'surfaces pull request lookup failures without escaping the action',
    () async {
      final first = _review(41, headBranch: 'feature/one', baseBranch: 'main');
      final second = _review(
        42,
        headBranch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final forge = _FakeStackForgeProvider()
        ..branchReview = second
        ..reviewLookupError = const ForgeRequestFailed('network unavailable');
      forge.byNumber
        ..[41] = first
        ..[42] = second;
      final container = _container(forge: forge);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .linkReviewStack(const <int>[41, 42]);

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.errorMessage, 'network unavailable');
      expect(state.action, isNull);
      expect(forge.linkStackCalls, 0);
    },
  );
}

class _FakeStackForgeProvider extends FakeForgeProvider
    implements ForgeStackProvider {
  HostedReviewStack? stack;
  int stackLoadCalls = 0;
  int linkStackCalls = 0;
  List<int>? linkedReviewNumbers;
  int? linkedStackNumber;
  String? linkedBaseBranch;
  int stackMergeCalls = 0;
  int? lastStackMergeReviewNumber;
  ReviewMergeMethod? lastStackMergeMethod;
  Object? reviewLookupError;

  @override
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final error = reviewLookupError;
    if (error != null) {
      throw error;
    }
    return super.getReviewByNumber(
      identity: identity,
      repoPath: repoPath,
      number: number,
    );
  }

  @override
  Future<HostedReviewStack?> getStackForReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
  }) async {
    stackLoadCalls++;
    return stack;
  }

  @override
  Future<HostedReviewStack> linkReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required List<int> reviewNumbers,
    int? stackNumber,
    String? baseBranch,
  }) async {
    linkStackCalls++;
    linkedReviewNumbers = List<int>.from(reviewNumbers);
    linkedStackNumber = stackNumber;
    linkedBaseBranch = baseBranch;
    final reviews = reviewNumbers.map((number) => byNumber[number]!).toList();
    stack = HostedReviewStack(
      number: stackNumber ?? 700,
      baseBranch: baseBranch ?? reviews.first.baseBranch ?? 'main',
      open: true,
      entries: <HostedReviewStackEntry>[
        for (final (index, review) in reviews.indexed)
          HostedReviewStackEntry(review: review, position: index + 1),
      ],
    );
    return stack!;
  }

  @override
  Future<void> mergeReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
    required ReviewMergeMethod method,
  }) async {
    stackMergeCalls++;
    lastStackMergeReviewNumber = reviewNumber;
    lastStackMergeMethod = method;
  }
}
