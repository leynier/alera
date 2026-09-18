part of 'workspace_pull_requests_panel_test.dart';

void _registerWorkspacePullRequestsPanelRemovalTests() {
  testWidgets(
    'merged pull requests default to Archive and keep the sidebar Remove Workspace flow',
    (tester) async {
      final now = DateTime.utc(2026, 7, 16);
      final project = Project(
        id: 'project-1',
        name: 'Alera',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      final workspace = Workspace(
        id: 'workspace-1',
        projectId: project.id,
        name: 'Feature login',
        branch: 'feature',
        path: '/repo-feature',
        createdAt: now,
        updatedAt: now,
        kind: .linked,
        status: .active,
      );
      final review = _review(123).copyWith(state: .merged);
      final forge = FakeForgeProvider()
        ..branchReview = review
        ..byNumber[123] = review;
      final linkedReviews = FakeLinkedReviewRepository()
        ..store[workspace.id] = LinkedReview.linked(
          workspaceId: workspace.id,
          provider: .github,
          number: 123,
          url: review.url,
        );
      final git = FakeGitBackend()
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        };
      final controller = _PanelWorkbenchController(
        WorkbenchState(
          projects: <Project>[project],
          workspacesByProject: <String, List<Workspace>>{
            project.id: <Workspace>[workspace],
          },
          activeProjectId: project.id,
          activeWorkspaceId: workspace.id,
          supportsArchive: true,
        ),
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
            linkedReviewRepositoryProvider.overrideWithValue(linkedReviews),
            settingsControllerProvider.overrideWithValue(.defaults),
            managedWorkspaceRuntimeProvider.overrideWithValue(null),
            workbenchControllerProvider.overrideWith(() => controller),
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

      expect(find.text('Archive Workspace'), findsOneWidget);
      expect(find.text('Remove Workspace'), findsNothing);
      expect(find.text('Unlink Pull Request'), findsNothing);

      await tester.tap(find.byTooltip('Pull Request Actions'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Workspace'), findsOneWidget);

      // The menu only selects the action; the primary button runs it.
      await tester.tap(find.text('Remove Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Workspace'), findsOneWidget);

      await tester.tap(find.text('Remove Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Workspace?'), findsOneWidget);
      expect(controller.deleteWorkspaceCalls, 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(controller.deleteWorkspaceCalls, 1);
      expect(controller.lastDeleteBranch, isTrue);
    },
  );
}
