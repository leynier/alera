part of 'alera_shell_page_test.dart';

void _registerAleraShellSidebarWorktreeRoleTests() {
  testWidgets('workspace rows mark the main worktree and linked worktrees', (
    tester,
  ) async {
    await _pumpShell(tester, state: _linkedWorkbenchState());

    expect(find.byKey(const Key('workspace-tray-home')), findsOneWidget);
    expect(find.byTooltip('Project folder'), findsOneWidget);
    expect(find.byIcon(AleraIcons.workspaceMain), findsOneWidget);
    expect(find.byKey(const Key('workspace-tray-worktree')), findsOneWidget);
    expect(find.byTooltip('Linked worktree'), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitFork), findsOneWidget);
  });

  testWidgets('folder project workspaces keep the project folder glyph', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 5, 22);
    final project = Project(
      id: 'project-folder',
      name: 'Notes',
      repoPath: '/repo/notes',
      createdAt: now,
      updatedAt: now,
      kind: .folder,
    );
    final workspace = Workspace(
      id: 'workspace-folder',
      projectId: project.id,
      name: 'Notes',
      branch: '',
      path: project.repoPath,
      createdAt: now,
      updatedAt: now,
      kind: .main,
      status: .active,
    );

    await _pumpShell(
      tester,
      state: WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
        bootstrapped: true,
      ),
    );

    expect(find.byIcon(AleraIcons.workspaceMain), findsOneWidget);
    expect(find.byTooltip('Project folder'), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitFork), findsNothing);
  });
}
