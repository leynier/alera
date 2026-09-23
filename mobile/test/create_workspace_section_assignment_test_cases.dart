part of 'create_workspace_screen_test.dart';

void _registerCreateWorkspaceSectionAssignmentTests() {
  testWidgets('Auto Assign Section hides without sections', (tester) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          navigatorKey: aleraNavigatorKey,
          home: const CreateWorkspaceScreen(
            hostId: 'host-1',
            projects: <ProjectSummary>[
              ProjectSummary(
                id: 'project-1',
                name: 'Alera',
                repoPath: '/repo/alera',
              ),
            ],
            workspaces: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Create Another'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto Assign Section'), findsNothing);
    expect(find.text('Create Another'), findsOneWidget);
  });

  testWidgets('Auto Assign Section defaults on when sections exist', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          navigatorKey: aleraNavigatorKey,
          home: CreateWorkspaceScreen(
            hostId: 'host-1',
            projects: const <ProjectSummary>[
              ProjectSummary(
                id: 'project-1',
                name: 'Alera',
                repoPath: '/repo/alera',
              ),
            ],
            workspaces: const [],
            sections: [
              WorkspaceSectionSummary(
                id: 'section-1',
                name: 'Work',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Auto Assign Section'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Auto Assign Section'),
          )
          .value,
      isTrue,
    );
  });
}
