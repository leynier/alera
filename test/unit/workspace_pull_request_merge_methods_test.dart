import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

HostedReview _review(
  int number, {
  HostedReviewState state = HostedReviewState.open,
  DateTime? createdAt,
  String? baseBranch,
  String? title,
}) => HostedReview(
  provider: .github,
  number: number,
  title: title ?? 'feat: $number',
  state: state,
  url: 'https://github.com/leynier/alera/pull/$number',
  baseBranch: baseBranch,
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
  test('loads merge methods for the review base branch', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(123, baseBranch: 'develop')
      ..mergeMethods = const <ReviewMergeMethod>[ReviewMergeMethod.squash];
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );

    expect(forge.mergeMethodsCalls, 1);
    expect(forge.lastMergeMethodsBaseBranch, 'develop');
    expect(state.mergeMethods, <ReviewMergeMethod>[ReviewMergeMethod.squash]);
  });

  test(
    'keeps the review visible when merge methods cannot be loaded',
    () async {
      final forge = FakeForgeProvider()
        ..branchReview = _review(123, baseBranch: 'main')
        ..mergeMethodsError = const ForgeRequestFailed(
          'GitHub did not return the repository merge methods.',
        );
      final container = _container(
        forge: forge,
        repo: FakeLinkedReviewRepository(),
      );
      addTearDown(container.dispose);

      final state = await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );

      expect(state.review?.number, 123);
      expect(state.mergeMethods, isEmpty);
      expect(state.errorMessage, isNull);
      expect(
        state.mergeMethodsErrorMessage,
        'GitHub did not return the repository merge methods.',
      );
    },
  );

  test(
    'refresh keeps a later review snapshot when merge methods fail',
    () async {
      final forge = FakeForgeProvider()
        ..branchReview = _review(123, baseBranch: 'main')
        ..mergeMethods = const <ReviewMergeMethod>[
          ReviewMergeMethod.mergeCommit,
        ]
        ..checks = const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .completed, conclusion: .success),
        ];
      final container = _container(
        forge: forge,
        repo: FakeLinkedReviewRepository(),
      );
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      forge
        ..branchReview = _review(
          123,
          baseBranch: 'main',
          title: 'feat: updated',
        )
        ..checks = const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .completed, conclusion: .failure),
        ]
        ..mergeMethodsError = const ForgeRequestFailed(
          'GitHub did not return the repository merge methods.',
        );

      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .refresh();
      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.review?.title, 'feat: updated');
      expect(state.checks.single.conclusion, ReviewCheckConclusion.failure);
      expect(state.mergeMethods, isEmpty);
      expect(
        state.mergeMethodsErrorMessage,
        'GitHub did not return the repository merge methods.',
      );
      expect(state.errorMessage, isNull);
    },
  );
}
