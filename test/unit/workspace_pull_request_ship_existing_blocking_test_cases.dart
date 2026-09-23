part of 'workspace_pull_request_ship_existing_test.dart';

void _registerWorkspacePullRequestShipExistingBlockingTests() {
  test('blocks Ship on the base branch when there are no unpushed commits or changes', () async {
    final git = FakeGitBackend()
      ..headBranch = 'main'
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitStatusResult = const GitStatusResult(entries: [])
      ..gitRangeContextResult = emptyShipRange;
    final forge = FakeForgeProvider();
    final aiAssist = FakeShipAiAssistService(const <Object>[]);
    final container = createShipTestContainer(
      git: git,
      forge: forge,
      linkedReviews: FakeLinkedReviewRepository(),
      aiAssist: aiAssist,
    );
    addTearDown(container.dispose);
    await container.read(
      workspacePullRequestControllerProvider(shipTestScope).future,
    );

    final result = await container
        .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
        .ship(
          baseBranch: 'main',
          draft: false,
          settings: AiAssistSettings.defaults,
          scope: PullRequestShipScope.staged,
        );

    expect(result, isA<CreateReviewFailure>());
    expect((result as CreateReviewFailure).message, 'No changes to ship.');
    expect(aiAssist.requests, isEmpty);
    expect(git.calls.where((call) => call.method == 'commit'), isEmpty);
    expect(
      git.calls.where((call) => call.method == 'createAndCheckoutBranch'),
      isEmpty,
    );
  });

  test('blocks Ship on the base branch when origin tracking is missing after fetch', () async {
    final git = FakeGitBackend()
      ..headBranch = 'main'
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitStatusResult = const GitStatusResult(entries: [])
      ..rangeContextError = const BranchNotFoundException(
        'refs/remotes/origin/main',
      );
    final forge = FakeForgeProvider();
    final aiAssist = FakeShipAiAssistService(const <Object>[]);
    final container = createShipTestContainer(
      git: git,
      forge: forge,
      linkedReviews: FakeLinkedReviewRepository(),
      aiAssist: aiAssist,
    );
    addTearDown(container.dispose);
    await container.read(
      workspacePullRequestControllerProvider(shipTestScope).future,
    );

    final result = await container
        .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
        .ship(
          baseBranch: 'main',
          draft: false,
          settings: AiAssistSettings.defaults,
          scope: PullRequestShipScope.staged,
        );

    expect(result, isA<CreateReviewFailure>());
    expect(
      (result as CreateReviewFailure).message,
      'Could not find refs/remotes/origin/main after fetch. Fetch the remote tracking branch before shipping.',
    );
    expect(aiAssist.requests, isEmpty);
    expect(git.calls.where((call) => call.method == 'commit'), isEmpty);
    expect(
      git.calls.where((call) => call.method == 'createAndCheckoutBranch'),
      isEmpty,
    );
  });

  test(
    'blocks staged Ship on a feature branch when uncommitted files remain',
    () async {
      const headBranch = 'feat/already-committed';
      final git = FakeGitBackend()
        ..headBranch = headBranch
        ..sourceBranches = <String>['main', headBranch]
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'README.md',
              area: .unstaged,
              status: .modified,
            ),
          ],
        )
        ..gitRangeContextResult = const GitRangeContext(
          baseRef: 'main',
          headBranch: headBranch,
          commits: <GitRangeCommit>[
            GitRangeCommit(
              oid: 'abc1234',
              subject: 'feat: already committed',
              message: 'feat: already committed',
            ),
          ],
          files: <GitRangeFile>[],
          patch: '',
        );
      final forge = FakeForgeProvider();
      final aiAssist = FakeShipAiAssistService(const <Object>[]);
      final container = createShipTestContainer(
        git: git,
        forge: forge,
        linkedReviews: FakeLinkedReviewRepository(),
        aiAssist: aiAssist,
      );
      addTearDown(container.dispose);
      await container.read(
        workspacePullRequestControllerProvider(shipTestScope).future,
      );

      final result = await container
          .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
          .ship(
            baseBranch: 'main',
            draft: false,
            settings: AiAssistSettings.defaults,
            scope: PullRequestShipScope.staged,
          );

      expect(result, isA<CreateReviewFailure>());
      expect(
        (result as CreateReviewFailure).message,
        'Stage at least one change before shipping.',
      );
      expect(aiAssist.requests, isEmpty);
      expect(git.calls.where((call) => call.method == 'rangeContext'), isEmpty);
      expect(git.calls.where((call) => call.method == 'push'), isEmpty);
    },
  );

  test('blocks staged Ship on a feature branch when staged and unstaged files remain', () async {
    const headBranch = 'feat/already-committed';
    final git = FakeGitBackend()
      ..headBranch = headBranch
      ..sourceBranches = <String>['main', headBranch]
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/ship.dart',
            area: .staged,
            status: .modified,
          ),
          GitChangeEntry(path: 'README.md', area: .unstaged, status: .modified),
        ],
      )
      ..gitRangeContextResult = const GitRangeContext(
        baseRef: 'main',
        headBranch: headBranch,
        commits: <GitRangeCommit>[
          GitRangeCommit(
            oid: 'abc1234',
            subject: 'feat: already committed',
            message: 'feat: already committed',
          ),
        ],
        files: <GitRangeFile>[],
        patch: '',
      );
    final forge = FakeForgeProvider();
    final aiAssist = FakeShipAiAssistService(const <Object>[]);
    final container = createShipTestContainer(
      git: git,
      forge: forge,
      linkedReviews: FakeLinkedReviewRepository(),
      aiAssist: aiAssist,
    );
    addTearDown(container.dispose);
    await container.read(
      workspacePullRequestControllerProvider(shipTestScope).future,
    );

    final result = await container
        .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
        .ship(
          baseBranch: 'main',
          draft: false,
          settings: AiAssistSettings.defaults,
          scope: PullRequestShipScope.staged,
        );

    expect(result, isA<CreateReviewFailure>());
    expect(
      (result as CreateReviewFailure).message,
      'Stage at least one change before shipping.',
    );
    expect(aiAssist.requests, isEmpty);
    expect(git.calls.where((call) => call.method == 'commit'), isEmpty);
    expect(git.calls.where((call) => call.method == 'push'), isEmpty);
    expect(forge.createCalls, 0);
  });

  test(
    'blocks staged Ship on main when staged and unstaged files remain',
    () async {
      final git = FakeGitBackend()
        ..headBranch = 'main'
        ..sourceBranches = <String>['main']
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/ship.dart',
              area: .staged,
              status: .modified,
            ),
            GitChangeEntry(
              path: 'README.md',
              area: .unstaged,
              status: .modified,
            ),
          ],
        )
        ..gitRangeContextResult = unpushedMainRange;
      final forge = FakeForgeProvider();
      final aiAssist = FakeShipAiAssistService(const <Object>[]);
      final container = createShipTestContainer(
        git: git,
        forge: forge,
        linkedReviews: FakeLinkedReviewRepository(),
        aiAssist: aiAssist,
      );
      addTearDown(container.dispose);
      await container.read(
        workspacePullRequestControllerProvider(shipTestScope).future,
      );

      final result = await container
          .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
          .ship(
            baseBranch: 'main',
            draft: false,
            settings: AiAssistSettings.defaults,
            scope: PullRequestShipScope.staged,
          );

      expect(result, isA<CreateReviewFailure>());
      expect(
        (result as CreateReviewFailure).message,
        'Stage at least one change before shipping.',
      );
      expect(aiAssist.requests, isEmpty);
      expect(
        git.calls.where((call) => call.method == 'createAndCheckoutBranch'),
        isEmpty,
      );
      expect(
        git.calls.where((call) => call.method == 'resetBranchToRef'),
        isEmpty,
      );
      expect(git.calls.where((call) => call.method == 'commit'), isEmpty);
      expect(git.calls.where((call) => call.method == 'push'), isEmpty);
      expect(forge.createCalls, 0);
    },
  );
}
