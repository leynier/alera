part of 'workspace_pull_request_controller_test.dart';

void _registerWorkspacePullRequestRevalidationTests() {
  test('merge rejects a changed head after confirmation', () async {
    final forge = FakeForgeProvider()
      ..branchReview = _review(123).copyWith(headSha: 'before');
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);
    final loaded = await container.read(
      workspacePullRequestControllerProvider(_scope).future,
    );
    forge.branchReview = _review(123).copyWith(headSha: 'after');
    final result = await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .mergeReview(
          .squash,
          expectedFingerprint: reviewActionFingerprint(loaded),
        );
    expect(result, isFalse);
    expect(forge.mergeCalls, 0);
    expect(
      container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!
          .review!
          .headSha,
      'after',
    );
  });
  test('merge revalidates newly failing checks and revoked access', () async {
    for (final revoked in [false, true]) {
      final forge = FakeForgeProvider()..branchReview = _review(123);
      final container = _container(
        forge: forge,
        repo: FakeLinkedReviewRepository(),
      );
      final loaded = await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      if (revoked) {
        forge.actionAccess = const ReviewActionAccess(canMerge: false);
      } else {
        forge.checks = [
          const ReviewCheck(
            name: 'CI',
            status: .completed,
            conclusion: .failure,
          ),
        ];
      }
      final result = await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .mergeReview(
            .squash,
            expectedFingerprint: reviewActionFingerprint(loaded),
          );
      expect(result, isFalse);
      expect(forge.mergeCalls, 0);
      container.dispose();
    }
  });

  test(
    'a created PR is visible even when its local link cannot be saved',
    () async {
      final forge = FakeForgeProvider()
        ..createResult = CreateReviewSuccess(_review(124));
      final links = FakeLinkedReviewRepository()
        ..saveError = StateError('disk unavailable');
      final container = _container(forge: forge, repo: links);
      addTearDown(container.dispose);
      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      final result = await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .createReview(
            const CreateReviewInput(
              provider: .github,
              title: 'Details',
              baseBranch: 'main',
              headBranch: 'feature',
            ),
            pushBranch: false,
          );
      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(result, isA<CreateReviewSuccess>());
      expect(state.review?.number, 124);
      expect(state.isBusy, isFalse);
      expect(state.errorMessage, contains('was created'));
      expect(forge.createCalls, 1);
    },
  );

  test('ready revalidation reports draft status instead of merging', () async {
    final draft = _review(123, state: .draft);
    final forge = FakeForgeProvider()..branchReview = draft;
    final container = _container(
      forge: forge,
      repo: FakeLinkedReviewRepository(),
    );
    addTearDown(container.dispose);
    final provider = workspacePullRequestControllerProvider(_scope);
    await container.read(provider.future);
    // Finish the panel's initial refresh before holding the action reload.
    await container.read(provider.notifier).refresh();
    final reload = Completer<HostedReview?>();
    forge.branchReviewLoader = () => reload.future;
    final action = container.read(provider.notifier).setReviewDraft(false);
    await Future<void>.value();
    expect(
      container.read(provider).value!.action,
      PullRequestAction.draftStatus,
    );
    expect(forge.draftStatusCalls, 0);
    reload.complete(draft);
    await action;
    expect(forge.lastDraftStatus, isFalse);
    expect(forge.mergeCalls, 0);
  });
}
