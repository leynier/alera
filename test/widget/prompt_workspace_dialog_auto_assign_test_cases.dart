part of 'prompt_workspace_dialog_test.dart';

void _registerPromptWorkspaceAutoAssignTests() {
  testWidgets('hides Auto Assign Section without workspace sections', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 30);
    final project = _project(id: 'project-1', name: 'Alera', now: now);
    final profile = _profile(id: 'profile-1', name: 'Codex Builder', now: now);

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
                required autoAssignSection,
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
              }) async => throw UnimplementedError(),
          launchAgent:
              ({
                required workspaceId,
                required profileId,
                required prompt,
                required clientMutationId,
                required requireIdempotency,
              }) async => throw UnimplementedError(),
          supportsIdempotentAgentLaunch: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Auto Assign Section'), findsNothing);
    expect(find.text('Create Another'), findsOneWidget);
  });

  testWidgets('forwards the section choice and assigns it after creation', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 30);
    final project = _project(id: 'project-1', name: 'Alera', now: now);
    final profile = _profile(id: 'profile-1', name: 'Codex Builder', now: now);
    var forwardedAutoAssign = false;
    final assignments = <String>[];

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
                required autoAssignSection,
              }) async {
                forwardedAutoAssign = autoAssignSection;
                return const GeneratedWorkspaceIdentity(
                  workspaceName: 'Prompt Workspace',
                  branchName: 'feat/prompt-workspace',
                  sectionId: 'section-1',
                );
              },
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
                  workspace: _workspace(
                    id: 'workspace-1',
                    projectId: project.id,
                    name: name,
                    branch: newBranchName,
                    kind: .linked,
                    now: now,
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
              }) async => AgentProfileLaunchResult(
                tabId: 'tab-1',
                agentType: profile.agentType,
                profileId: profileId,
                idempotent: true,
              ),
          supportsIdempotentAgentLaunch: () async => true,
          hasWorkspaceSections: true,
          assignSection: (workspaceId, sectionId) async {
            assignments.add('$workspaceId $sectionId');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Auto Assign Section'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Build workspace creation',
    );
    final submit = find.text('Create And Start Agent');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(forwardedAutoAssign, isTrue);
    expect(assignments, <String>['workspace-1 section-1']);
  });

  testWidgets('unchecking Auto Assign Section skips the assignment', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 30);
    final project = _project(id: 'project-1', name: 'Alera', now: now);
    final profile = _profile(id: 'profile-1', name: 'Codex Builder', now: now);
    var forwardedAutoAssign = true;
    final assignments = <String>[];

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
                required autoAssignSection,
              }) async {
                forwardedAutoAssign = autoAssignSection;
                return const GeneratedWorkspaceIdentity(
                  workspaceName: 'Prompt Workspace',
                  branchName: 'feat/prompt-workspace',
                  sectionId: 'section-1',
                );
              },
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
                  workspace: _workspace(
                    id: 'workspace-1',
                    projectId: project.id,
                    name: name,
                    branch: newBranchName,
                    kind: .linked,
                    now: now,
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
              }) async => AgentProfileLaunchResult(
                tabId: 'tab-1',
                agentType: profile.agentType,
                profileId: profileId,
                idempotent: true,
              ),
          supportsIdempotentAgentLaunch: () async => true,
          hasWorkspaceSections: true,
          assignSection: (workspaceId, sectionId) async {
            assignments.add('$workspaceId $sectionId');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Auto Assign Section'));
    await tester.tap(find.text('Auto Assign Section'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Build workspace creation',
    );
    final submit = find.text('Create And Start Agent');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(forwardedAutoAssign, isFalse);
    expect(assignments, isEmpty);
  });
}
