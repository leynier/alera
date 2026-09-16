part of 'prompt_workspace_dialog_test.dart';

class _PromptSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

Project _project({
  required String id,
  required String name,
  required DateTime now,
}) {
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/${name.toLowerCase()}',
    createdAt: now,
    updatedAt: now,
  );
}

AgentProfile _profile({
  required String id,
  required String name,
  String agentType = 'codex',
  String command = 'codex',
  required DateTime now,
}) {
  return AgentProfile(
    id: id,
    name: name,
    agentType: agentType,
    command: command,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpEnqueuePromptDialog(
  WidgetTester tester, {
  required List<Project> projects,
  required AgentProfile profile,
  required Future<List<String>> Function(Project project) loadBranches,
  required List<PromptWorkspaceCreateRequest> requests,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(_PromptSettingsController.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showDialog<PromptWorkspaceDialogResult>(
                  context: context,
                  builder: (_) => PromptWorkspaceDialog(
                    projects: projects,
                    agentProfiles: <AgentProfile>[profile],
                    initialUseProjectCheckout: false,
                    loadBranches: loadBranches,
                    checkBranchExists: (_, _) async => false,
                    workspaceBranches: (_) => const <String>{},
                    parentWorkspaces: const <Workspace>[],
                    generateIdentity: ({
                      required operationId,
                      required projectId,
                      required prompt,
                    }) async => throw UnimplementedError(),
                    cancelGeneration: (_) async {},
                    createWorkspace: ({
                      required project,
                      required sourceBranch,
                      required newBranchName,
                      required name,
                      parentWorkspaceId,
                      hostId,
                      issueUrl,
                    }) async => throw UnimplementedError(),
                    launchAgent: ({
                      required workspaceId,
                      required profileId,
                      required prompt,
                      required clientMutationId,
                      required requireIdempotency,
                    }) async => throw UnimplementedError(),
                    supportsIdempotentAgentLaunch: () async => true,
                    enqueuePrompt: (request) {
                      requests.add(request);
                      return Future<void>.value();
                    },
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
}

void _selectPromptProject(WidgetTester tester, Project project) {
  tester
      .widget<AleraDropdownField<Project>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AleraDropdownField<Project> &&
              widget.labelText == 'Project',
        ),
      )
      .onChanged(project);
}

Future<void> _submitPromptWithControlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(.controlLeft);
  await tester.sendKeyEvent(.enter);
  await tester.sendKeyUpEvent(.controlLeft);
  await tester.pump();
}

Workspace _workspace({
  required String id,
  required String projectId,
  required String name,
  required String branch,
  required WorkspaceKind kind,
  required DateTime now,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: branch,
    path: '/repo/$projectId/$id',
    kind: kind,
    status: .active,
    createdAt: now,
    updatedAt: now,
  );
}
