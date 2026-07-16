import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
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

const _review = HostedReview(
  provider: GitHostingProvider.github,
  number: 123,
  title: 'feat: comments',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/123',
  headBranch: 'feature',
);

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
  test('loads comments with the review snapshot', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review
      ..comments = <ReviewComment>[
        ReviewComment(
          id: 'c1',
          author: 'reviewer',
          body: 'Looks good',
          createdAt: DateTime.utc(2026, 7, 16),
          kind: ReviewCommentKind.conversation,
        ),
      ];
    final container = _container(forge);
    addTearDown(container.dispose);

    final state = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );

    expect(state.comments.single.body, 'Looks good');
    expect(forge.commentsCalls, 1);
  });

  test('adds a conversation comment and reloads the comments', () async {
    final forge = FakeForgeProvider()..branchReview = _review;
    final container = _container(forge);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    final posted = await controller.addReviewComment('  Ready to merge  ');

    expect(posted, isTrue);
    expect(forge.addCommentCalls, 1);
    expect(forge.lastCommentBody, 'Ready to merge');
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.comments.single.body, 'Ready to merge');
    expect(state.action, isNull);
    expect(state.errorMessage, isNull);
  });

  test('keeps the current comments when posting fails', () async {
    final existing = ReviewComment(
      id: 'c1',
      author: 'reviewer',
      body: 'Please update this',
      createdAt: DateTime.utc(2026, 7, 16),
      kind: ReviewCommentKind.review,
      path: 'lib/a.dart',
      line: 12,
    );
    final forge = FakeForgeProvider()
      ..branchReview = _review
      ..comments = <ReviewComment>[existing]
      ..addCommentError = StateError('permission denied');
    final container = _container(forge);
    addTearDown(container.dispose);

    await container.read(workspacePullRequestControllerProvider(_scope).future);
    final controller = container.read(
      workspacePullRequestControllerProvider(_scope).notifier,
    );
    final posted = await controller.addReviewComment('Done');

    expect(posted, isFalse);
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.comments, <ReviewComment>[existing]);
    expect(state.errorMessage, contains('permission denied'));
  });
}
