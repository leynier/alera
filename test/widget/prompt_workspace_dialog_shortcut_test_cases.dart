part of 'prompt_workspace_dialog_test.dart';

void _registerPromptWorkspaceShortcutTests() {
  testWidgets('Control+Enter submits From Prompt', (tester) async {
    final now = DateTime.utc(2026, 7, 29);
    final project = _project(id: 'project-1', name: 'Alera', now: now);
    final profile = _profile(id: 'profile-1', name: 'Codex Builder', now: now);
    String? launchedPrompt;

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
                onPressed: () async {
                  await showDialog<PromptWorkspaceDialogResult>(
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
                            return WorkspaceCreationResult(
                              workspace: Workspace(
                                id: 'workspace-1',
                                projectId: project.id,
                                name: name,
                                branch: newBranchName,
                                sourceBranch: sourceBranch,
                                path: '/repo/alera-workspace',
                                kind: .linked,
                                status: .active,
                                createdAt: now,
                                updatedAt: now,
                              ),
                              setupReport: .empty,
                            );
                          },
                      launchAgent:
                          ({
                            required workspaceId,
                            required profileId,
                            required prompt,
                            required clientMutationId,
                            required requireIdempotency,
                          }) async {
                            launchedPrompt = prompt;
                            return AgentProfileLaunchResult(
                              tabId: 'tab-1',
                              agentType: profile.agentType,
                              profileId: profileId,
                              idempotent: true,
                            );
                          },
                      supportsIdempotentAgentLaunch: () async => true,
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Build workspace creation',
    );
    await tester.sendKeyEvent(.enter);
    await tester.pump();
    expect(launchedPrompt, isNull);

    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyEvent(.enter);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(launchedPrompt, 'Build workspace creation');
  });

  testWidgets(
    'Control+Enter waits for the new project branches before submitting',
    (tester) async {
      final now = DateTime.utc(2026, 7, 29);
      final alera = _project(id: 'project-alera', name: 'Alera', now: now);
      final orca = _project(id: 'project-orca', name: 'Orca', now: now);
      final profile = _profile(
        id: 'profile-1',
        name: 'Codex Builder',
        now: now,
      );
      final orcaBranches = Completer<List<String>>();
      final requests = <PromptWorkspaceCreateRequest>[];

      await _pumpEnqueuePromptDialog(
        tester,
        projects: <Project>[alera, orca],
        profile: profile,
        loadBranches: (project) async {
          if (project.id == orca.id) {
            return orcaBranches.future;
          }
          return <String>['main'];
        },
        requests: requests,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Initial Prompt'),
        'Build workspace creation',
      );

      _selectPromptProject(tester, orca);
      await tester.pump();
      await _submitPromptWithControlEnter(tester);
      expect(requests, isEmpty);

      orcaBranches.complete(const <String>['develop']);
      await tester.pumpAndSettle();
      await _submitPromptWithControlEnter(tester);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.project.id, orca.id);
      expect(requests.single.sourceBranch, 'develop');
      expect(requests.single.prompt, 'Build workspace creation');
    },
  );

  testWidgets(
    'Control+Enter does not keep the previous project branch after a failed load',
    (tester) async {
      final now = DateTime.utc(2026, 7, 29);
      final alera = _project(id: 'project-alera', name: 'Alera', now: now);
      final orca = _project(id: 'project-orca', name: 'Orca', now: now);
      final profile = _profile(
        id: 'profile-1',
        name: 'Codex Builder',
        now: now,
      );
      final orcaBranches = Completer<List<String>>();
      final requests = <PromptWorkspaceCreateRequest>[];

      await _pumpEnqueuePromptDialog(
        tester,
        projects: <Project>[alera, orca],
        profile: profile,
        loadBranches: (project) async {
          if (project.id == orca.id) {
            return orcaBranches.future;
          }
          return <String>['main'];
        },
        requests: requests,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Initial Prompt'),
        'Build workspace creation',
      );

      _selectPromptProject(tester, orca);
      await tester.pump();
      orcaBranches.completeError(StateError('branches unavailable'));
      await tester.pumpAndSettle();
      await _submitPromptWithControlEnter(tester);
      await tester.pump();

      expect(requests, isEmpty);
      expect(
        find.text('Complete the prompt, project, branch, and agent profile.'),
        findsOneWidget,
      );
    },
  );
}
