part of 'workspace_explorer_test.dart';

void _registerWorkspaceExplorerContextSidebarTests() {
  testWidgets(
    'context sidebar keeps source control tabs and explains missing git scope',
    (tester) async {
      final service = _FakeWorkspaceFileService();

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: WorkspaceContextSidebar(
                workspace: _workspace(),
                prefs: WorkbenchViewPrefs.defaults.copyWith(
                  activeContextPanelTab: WorkbenchContextPanelTab.gitDiff,
                ),
                onToggleVisible: () {},
                onResize: (_) {},
                onSetContextPanelTab: (_) {},
                onSetExplorerMode: (_) {},
                onSetGitDiffViewMode: (_) {},
                onOpenFile: (_) {},
                onOpenGitDiff:
                    ({
                      relativePath,
                      area,
                      gitDiffRoot,
                      required scope,
                    }) async {},
                onOpenGitCommitDiff:
                    ({
                      relativePath,
                      oldPath,
                      required scope,
                      gitDiffRoot,
                      required commitOid,
                      parentOid,
                      required compareRef,
                      subject,
                      message,
                    }) async {},
                onOpenSearchMatch: (_) {},
                onPathMoved: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Explorer'), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Source Control'), findsOneWidget);
      expect(find.byTooltip('Pull Request'), findsOneWidget);
      expect(find.text('Source Control Unavailable'), findsOneWidget);
      expect(
        find.text(
          'This workspace is not connected to a Git repository, so there are no changes to show.',
        ),
        findsOneWidget,
      );
      expect(find.byType(WorkspaceExplorer), findsNothing);

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: WorkspaceContextSidebar(
                workspace: _workspace(),
                prefs: WorkbenchViewPrefs.defaults.copyWith(
                  activeContextPanelTab: WorkbenchContextPanelTab.pullRequests,
                  rightSidebarVisible: false,
                ),
                onToggleVisible: () {},
                onResize: (_) {},
                onSetContextPanelTab: (_) {},
                onSetExplorerMode: (_) {},
                onSetGitDiffViewMode: (_) {},
                onOpenFile: (_) {},
                onOpenGitDiff:
                    ({
                      relativePath,
                      area,
                      gitDiffRoot,
                      required scope,
                    }) async {},
                onOpenGitCommitDiff:
                    ({
                      relativePath,
                      oldPath,
                      required scope,
                      gitDiffRoot,
                      required commitOid,
                      parentOid,
                      required compareRef,
                      subject,
                      message,
                    }) async {},
                onOpenSearchMatch: (_) {},
                onPathMoved: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Expand panel'), findsOneWidget);
      expect(find.byTooltip('Source Control'), findsOneWidget);
      expect(find.byTooltip('Pull Request'), findsOneWidget);

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: WorkspaceContextSidebar(
                workspace: _workspace(),
                prefs: WorkbenchViewPrefs.defaults.copyWith(
                  activeContextPanelTab: WorkbenchContextPanelTab.pullRequests,
                ),
                onToggleVisible: () {},
                onResize: (_) {},
                onSetContextPanelTab: (_) {},
                onSetExplorerMode: (_) {},
                onSetGitDiffViewMode: (_) {},
                onOpenFile: (_) {},
                onOpenGitDiff:
                    ({
                      relativePath,
                      area,
                      gitDiffRoot,
                      required scope,
                    }) async {},
                onOpenGitCommitDiff:
                    ({
                      relativePath,
                      oldPath,
                      required scope,
                      gitDiffRoot,
                      required commitOid,
                      parentOid,
                      required compareRef,
                      subject,
                      message,
                    }) async {},
                onOpenSearchMatch: (_) {},
                onPathMoved: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Source Control'), findsOneWidget);
      expect(find.byTooltip('Pull Request'), findsOneWidget);
      expect(find.text('Pull Request Unavailable'), findsOneWidget);
      expect(
        find.text(
          'This workspace is not connected to a Git repository, so there are no Pull Requests to show.',
        ),
        findsOneWidget,
      );
    },
  );
}
