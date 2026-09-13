part of 'prompt_workspace_dialog_test.dart';

void _registerPromptWorkspaceModeTests() {
  testWidgets('switches between From Prompt and Manual in the same dialog', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 29);
    final project = _project(id: 'project-1', name: 'Alera', now: now);
    final profile = _profile(id: 'profile-1', name: 'Codex Builder', now: now);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            _PromptSettingsController.new,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<PromptWorkspaceDialogResult>(
                    context: context,
                    builder: (_) => PromptWorkspaceDialog(
                      projects: <Project>[project],
                      agentProfiles: <AgentProfile>[profile],
                      loadBranches: (_) async => <String>['main'],
                      checkBranchExists: (_, _) async => false,
                      workspaceBranches: (_) => const <String>{},
                      parentWorkspaces: const <Workspace>[],
                      generateIdentity:
                          ({
                            required operationId,
                            required projectId,
                            required prompt,
                          }) async => const GeneratedWorkspaceIdentity(
                            workspaceName: 'Prompt Workspace',
                            branchName: 'feat/prompt-workspace',
                          ),
                      cancelGeneration: (_) async {},
                      createWorkspace:
                          ({
                            required project,
                            required sourceBranch,
                            required newBranchName,
                            required name,
                            parentWorkspaceId,
                            hostId,
                            issueUrl,
                          }) async {
                            throw UnimplementedError();
                          },
                      launchAgent:
                          ({
                            required workspaceId,
                            required profileId,
                            required prompt,
                            required clientMutationId,
                            required requireIdempotency,
                          }) async {
                            throw UnimplementedError();
                          },
                      supportsIdempotentAgentLaunch: () async => true,
                      manualForm: const Text('Manual Workspace Form'),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Initial Prompt'), findsOneWidget);
    expect(find.text('Continue Manually'), findsNothing);
    expect(find.text('Manual Workspace Form'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Keep this prompt',
    );
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('Manual Workspace Form'), findsOneWidget);
    expect(find.text('Initial Prompt'), findsNothing);
    expect(find.text('Continue Manually'), findsNothing);

    await tester.tap(find.text('From Prompt'));
    await tester.pumpAndSettle();

    expect(find.text('Initial Prompt'), findsOneWidget);
    expect(find.text('Manual Workspace Form'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
          .controller
          ?.text,
      'Keep this prompt',
    );
  });
}
