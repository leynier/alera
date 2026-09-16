part of 'create_workspace_screen_test.dart';

void _registerCreateWorkspaceShortcutTests() {
  for (final shortcut in <({String name, LogicalKeyboardKey modifier})>[
    (name: 'Control', modifier: .controlLeft),
    (name: 'Cmd', modifier: .metaLeft),
  ]) {
    testWidgets('From Prompt submits with ${shortcut.name}+Enter', (
      tester,
    ) async {
      final client = FakeTerminalClient()
        ..projectBranches = const <String>['main'];
      addTearDown(client.dispose);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceClientProvider('host-1')
                .overrideWith((ref) async => client),
            terminalClientProvider('host-1')
                .overrideWith((ref) async => client),
          ],
          child: MaterialApp(
            navigatorKey: aleraNavigatorKey,
            home: const CreateWorkspaceScreen(
              supportsSharedCheckoutWorkspaces: true,
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
        find.widgetWithText(TextField, 'Initial Prompt'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Initial Prompt'),
        'Build offline support',
      );
      await tester.sendKeyDownEvent(shortcut.modifier);
      await tester.sendKeyEvent(.enter);
      await tester.sendKeyUpEvent(shortcut.modifier);
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (client.calls.any((call) => call.startsWith('launchAgentProfile'))) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(find.byType(CreateWorkspaceScreen), findsNothing);
      expect(find.byType(WorkspaceTabsScreen), findsOneWidget);
      expect(
        client.calls,
        contains('launchAgentProfile created profile-1 Build offline support'),
      );
    });
  }

  testWidgets('From Prompt ignores a second Command+Enter while creating', (
    tester,
  ) async {
    final identityReady = Completer<void>();
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main']
      ..generateWorkspaceIdentityDelay = identityReady.future;
    addTearDown(client.dispose);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          navigatorKey: aleraNavigatorKey,
          home: const CreateWorkspaceScreen(
            supportsSharedCheckoutWorkspaces: true,
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
      find.widgetWithText(TextField, 'Initial Prompt'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Build offline support',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create Another'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Another'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextField, 'Initial Prompt'));
    await tester.pump();
    await tester.sendKeyDownEvent(.controlLeft);
    expect(await tester.sendKeyEvent(.enter), isTrue);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.sendKeyDownEvent(.controlLeft);
    expect(await tester.sendKeyEvent(.enter), isTrue);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pump();
    expect(
      client.calls.where(
        (call) => call.startsWith('generateWorkspaceIdentity'),
      ),
      hasLength(1),
    );
    expect(find.text('Workspace creation is already running.'), findsNothing);

    identityReady.complete();
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (client.calls.any((call) => call.startsWith('launchAgentProfile'))) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(
      client.calls.where(
        (call) => call.startsWith('generateWorkspaceIdentity'),
      ),
      hasLength(1),
    );
    expect(find.text('Workspace creation is already running.'), findsNothing);
    expect(find.byType(CreateWorkspaceScreen), findsOneWidget);
  });
}
