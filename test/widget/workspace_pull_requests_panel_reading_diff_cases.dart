part of 'workspace_pull_requests_panel_test.dart';

void _registerWorkspacePullRequestsPanelReadingDiffTests() {
  testWidgets('opens the linked pull request diff from its exact hosted head', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 10);
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: 'project-1',
      name: 'Feature',
      branch: 'feature',
      path: '/repo',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
    );
    final review = _review(385);
    final forge = FakeForgeProvider()..branchReview = review;
    final git = FakeGitBackend()
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitRangeContextResult = const GitRangeContext(
        baseRef: 'main',
        headOid: 'hosted-head',
        mergeBase: 'merge-base',
        commits: <GitRangeCommit>[],
        files: <GitRangeFile>[],
        patch: '',
      );
    late _PanelWorkbenchController workbench;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveHostingProviderOverrideProvider.overrideWith(
            (ref, projectId) async => null,
          ),
          gitBackendProvider.overrideWithValue(git),
          forgeProviderRegistryProvider.overrideWithValue(
            ForgeProviderRegistry(<ForgeProvider>[forge]),
          ),
          linkedReviewRepositoryProvider.overrideWithValue(
            FakeLinkedReviewRepository(),
          ),
          workbenchControllerProvider.overrideWith(
            () => workbench = _PanelWorkbenchController(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: WorkspacePullRequestsPanel(
                workspace: workspace,
                repoPath: workspace.path,
                gitDiffRoot: 'packages/app',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Pull Request Diff'));
    await tester.pumpAndSettle();

    expect(
      git.calls
          .where((call) => call.method == 'fetchHostedReviewRange')
          .single
          .args,
      <String, Object?>{
        'path': '/repo',
        'remote': 'origin',
        'baseBranch': 'main',
        'headSha': 'head-385',
        'headRemote': null,
        'comparisonBaseSha': 'base-385',
        'mergeCommitSha': 'merge-385',
        'reviewRef': 'refs/pull/385/head',
      },
    );
    expect(
      git.calls.where((call) => call.method == 'rangeContext').single.args,
      <String, Object?>{
        'path': '/repo',
        'baseRef': 'main',
        'commitLimit': 40,
        'headRef': 'head-385',
      },
    );
    expect(workbench.openedPullRequestDiffs, <Object>[
      (
        number: 385,
        commitOid: 'hosted-head',
        gitDiffRoot: 'packages/app',
        parentOid: 'merge-base',
      ),
    ]);
    expect(
      git.calls.where((call) => call.method == 'releaseHostedReviewRange'),
      isEmpty,
    );
  });

  testWidgets('opens an Azure fork diff from the source repository', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 10);
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: 'project-1',
      name: 'Feature',
      branch: 'feature',
      path: '/repo',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
    );
    const sourceUrl = 'https://dev.azure.com/myorg/fork/_git/alera';
    final review = HostedReview(
      provider: GitHostingProvider.azureDevops,
      number: 42,
      title: 'feat: fork',
      state: HostedReviewState.open,
      url: 'https://dev.azure.com/myorg/project/_git/alera/pullrequest/42',
      baseBranch: 'main',
      headBranch: 'feature',
      headSha: 'fork-head',
      headRepositoryUrl: sourceUrl,
      comparisonBaseSha: 'target-base',
    );
    final forge = FakeForgeProvider()
      ..provider = GitHostingProvider.azureDevops
      ..branchReview = review;
    final git = FakeGitBackend()
      ..remotesByName = <String, String?>{
        'origin': 'https://dev.azure.com/myorg/project/_git/alera',
      }
      ..gitRangeContextResult = const GitRangeContext(
        baseRef: 'main',
        headOid: 'fork-head',
        mergeBase: 'target-base',
        commits: <GitRangeCommit>[],
        files: <GitRangeFile>[],
        patch: '',
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveHostingProviderOverrideProvider.overrideWith(
            (ref, projectId) async => null,
          ),
          gitBackendProvider.overrideWithValue(git),
          forgeProviderRegistryProvider.overrideWithValue(
            ForgeProviderRegistry(<ForgeProvider>[forge]),
          ),
          linkedReviewRepositoryProvider.overrideWithValue(
            FakeLinkedReviewRepository(),
          ),
          workbenchControllerProvider.overrideWith(
            _PanelWorkbenchController.new,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: WorkspacePullRequestsPanel(
                workspace: workspace,
                repoPath: workspace.path,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Pull Request Diff'));
    await tester.pumpAndSettle();

    final call = git.calls
        .where((call) => call.method == 'fetchHostedReviewRange')
        .single;
    expect(call.args['remote'], 'origin');
    expect(call.args['headRemote'], sourceUrl);
    expect(call.args['reviewRef'], 'refs/heads/feature');
  });

  testWidgets('releases hosted objects when the diff cannot be opened', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 10);
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: 'project-1',
      name: 'Feature',
      branch: 'feature',
      path: '/repo',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
    );
    final forge = FakeForgeProvider()..branchReview = _review(385);
    final git = FakeGitBackend()
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..rangeContextError = const GitInternalException('missing range');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveHostingProviderOverrideProvider.overrideWith(
            (ref, projectId) async => null,
          ),
          gitBackendProvider.overrideWithValue(git),
          forgeProviderRegistryProvider.overrideWithValue(
            ForgeProviderRegistry(<ForgeProvider>[forge]),
          ),
          linkedReviewRepositoryProvider.overrideWithValue(
            FakeLinkedReviewRepository(),
          ),
          workbenchControllerProvider.overrideWith(
            _PanelWorkbenchController.new,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: WorkspacePullRequestsPanel(
                workspace: workspace,
                repoPath: workspace.path,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Pull Request Diff'));
    await tester.pumpAndSettle();

    expect(
      git.calls
          .where((call) => call.method == 'releaseHostedReviewRange')
          .single
          .args,
      <String, Object?>{
        'path': '/repo',
        'retentionId': '00000000000000000000000000000001',
      },
    );
  });
}
