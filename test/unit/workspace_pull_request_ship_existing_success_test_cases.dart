part of 'workspace_pull_request_ship_existing_test.dart';

void _registerWorkspacePullRequestShipExistingSuccessTests() {
  test(
    'ships existing commits on a feature branch with a clean working tree',
    () async {
      const headBranch = 'feat/already-committed';
      final git = FakeGitBackend()
        ..headBranch = headBranch
        ..sourceBranches = <String>['main', headBranch]
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..gitStatusResult = const GitStatusResult(entries: [])
        ..gitRangeContextResult = const GitRangeContext(
          baseRef: 'main',
          headBranch: headBranch,
          commits: <GitRangeCommit>[
            GitRangeCommit(
              oid: 'abc1234',
              subject: 'feat: already committed',
              message: 'feat: already committed\n\nReady to open a PR.',
            ),
          ],
          files: <GitRangeFile>[
            GitRangeFile(
              path: 'lib/feature.dart',
              status: .added,
              added: 12,
              removed: 0,
            ),
          ],
          patch: 'diff --git a/lib/feature.dart b/lib/feature.dart',
        );
      final review = shipTestReview(706, headBranch: headBranch);
      final forge = FakeForgeProvider()
        ..createResult = CreateReviewSuccess(review)
        ..byNumber[706] = review;
      final aiAssist = FakeShipAiAssistService(<Object>[
        const AiAssistResult(
          text: 'Already committed work\n\nOpen a PR from existing commits.',
          agentLabel: 'Codex',
        ),
      ]);
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

      expect(result, isA<CreateReviewSuccess>());
      final methods = git.calls.map((call) => call.method).toList();
      expect(methods, isNot(contains('stage')));
      expect(methods, isNot(contains('commit')));
      expect(methods, isNot(contains('createAndCheckoutBranch')));
      expect(methods, containsAll(<String>['rangeContext', 'push']));
      expect(
        aiAssist.requests.map((request) => request.operation),
        <AiAssistOperation>[AiAssistOperation.pullRequestDetails],
      );
      expect(forge.lastCreateInput?.headBranch, headBranch);
      expect(forge.lastCreateInput?.title, 'Already committed work');
    },
  );

  test(
    'moves unpushed commits on main onto a ship branch before opening the PR',
    () async {
      const headBranch = 'ship/local-main-commit';
      final git = FakeGitBackend()
        ..headBranch = 'main'
        ..sourceBranches = <String>['main']
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..gitStatusResult = const GitStatusResult(entries: [])
        ..gitRangeContextResult = unpushedMainRange;
      final review = shipTestReview(707, headBranch: headBranch);
      final forge = FakeForgeProvider()
        ..createResult = CreateReviewSuccess(review)
        ..byNumber[707] = review;
      final aiAssist = FakeShipAiAssistService(<Object>[
        const AiAssistResult(
          text: 'Local main commit\n\nMove unpushed commits off main.',
          agentLabel: 'Codex',
        ),
      ]);
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

      expect(result, isA<CreateReviewSuccess>());
      final methods = git.calls.map((call) => call.method).toList();
      expect(methods, containsAll(<String>['fetch', 'rangeContext']));
      expect(methods, isNot(contains('commit')));
      expect(
        methods.indexOf('createAndCheckoutBranch'),
        lessThan(methods.indexOf('resetBranchToRef')),
      );
      expect(
        methods.indexOf('resetBranchToRef'),
        lessThan(methods.indexOf('push')),
      );
      final branchCall = git.calls.singleWhere(
        (call) => call.method == 'createAndCheckoutBranch',
      );
      expect(branchCall.args['branch'], headBranch);
      final resetCall = git.calls.singleWhere(
        (call) => call.method == 'resetBranchToRef',
      );
      expect(resetCall.args['branch'], 'main');
      expect(resetCall.args['targetRef'], 'refs/remotes/origin/main');
      expect(resetCall.args['expectedOid'], 'abc1234');
      final createCall = git.calls.singleWhere(
        (call) => call.method == 'createAndCheckoutBranch',
      );
      expect(createCall.args['expectedHead'], 'main');
      expect(createCall.args['expectedOid'], 'abc1234');
      expect(forge.lastCreateInput?.headBranch, headBranch);
      expect(forge.lastCreateInput?.baseBranch, 'main');
      expect(aiAssist.requests, hasLength(1));
      expect(
        aiAssist.requests.single.operation,
        AiAssistOperation.pullRequestDetails,
      );
    },
  );

  test('commits staged changes after moving unpushed main commits onto a ship branch', () async {
    const headBranch = 'ship/add-unpushed-and-staged';
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
        ],
      )
      ..gitRangeContextResult = unpushedMainRange;
    final review = shipTestReview(708, headBranch: headBranch);
    final forge = FakeForgeProvider()
      ..createResult = CreateReviewSuccess(review)
      ..byNumber[708] = review;
    final aiAssist = FakeShipAiAssistService(<Object>[
      const AiAssistResult(
        text: 'feat: add unpushed and staged',
        agentLabel: 'Codex',
      ),
      const AiAssistResult(
        text: 'Add unpushed and staged\n\nKeep both on the ship branch.',
        agentLabel: 'Codex',
      ),
    ]);
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

    expect(result, isA<CreateReviewSuccess>());
    final methods = git.calls.map((call) => call.method).toList();
    expect(
      methods.indexOf('createAndCheckoutBranch'),
      lessThan(methods.indexOf('resetBranchToRef')),
    );
    expect(
      methods.indexOf('resetBranchToRef'),
      lessThan(methods.indexOf('commit')),
    );
    expect(forge.lastCreateInput?.headBranch, headBranch);
  });
}
