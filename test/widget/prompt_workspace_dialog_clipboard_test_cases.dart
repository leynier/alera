part of 'prompt_workspace_dialog_test.dart';

void _registerPromptWorkspaceClipboardTests() {
  testWidgets('pastes an image path into the prompt at the caret', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 30);
    final project = _project(id: 'project-1', name: 'Alera', now: now);
    final profile = _profile(id: 'profile-1', name: 'Codex Builder', now: now);
    final clipboard = _FakePromptWorkspaceClipboard(
      imagePath: '/tmp/alera-paste-\x1b.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PromptWorkspaceDialog(
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
              }) async => WorkspaceCreationResult(
                workspace: _workspace(
                  id: 'workspace-1',
                  projectId: project.id,
                  name: name,
                  branch: newBranchName,
                  kind: .linked,
                  now: now,
                ),
                setupReport: .empty,
              ),
          launchAgent:
              ({
                required workspaceId,
                required profileId,
                required prompt,
                required clientMutationId,
                required requireIdempotency,
              }) async => const AgentProfileLaunchResult(
                tabId: 'tab-1',
                agentType: 'codex',
                profileId: 'profile-1',
                idempotent: true,
              ),
          supportsIdempotentAgentLaunch: () async => true,
          clipboard: clipboard,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final promptField = find.widgetWithText(TextField, 'Initial Prompt');
    await tester.enterText(promptField, 'Review this ');
    final focusContext = tester.binding.focusManager.primaryFocus?.context;
    expect(focusContext, isNotNull);
    Actions.invoke(focusContext!, const PasteTextIntent(.keyboard));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(promptField).controller?.text,
      'Review this /tmp/alera-paste-\u241b.png',
    );
    expect(clipboard.imageReads, 1);
  });

  testWidgets('keeps the default text paste when no image is available', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': 'from clipboard'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: 'Before ');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextField(
            controller: controller,
            onPaste: () async => false,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    final focusContext = tester.binding.focusManager.primaryFocus?.context;
    expect(focusContext, isNotNull);
    Actions.invoke(focusContext!, const PasteTextIntent(.keyboard));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.text, 'Before from clipboard');
  });
}

final class _FakePromptWorkspaceClipboard({final String? imagePath})
    implements PromptWorkspaceClipboard {
  int imageReads = 0;

  @override
  Future<String?> readText() async => null;

  @override
  Future<String?> saveImageAsTempFile() async {
    imageReads += 1;
    return imagePath;
  }
}
