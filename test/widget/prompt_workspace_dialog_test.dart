import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/presentation/prompt_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates an AI-named workspace and launches the profile', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 29);
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: now,
      updatedAt: now,
    );
    final profile = AgentProfile(
      id: 'profile-1',
      name: 'Codex Builder',
      agentType: 'codex',
      command: 'codex',
      createdAt: now,
      updatedAt: now,
    );
    PromptWorkspaceDialogResult? dialogResult;
    String? generatedPrompt;
    String? createdBranch;
    String? createdName;
    String? launchedPrompt;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                dialogResult = await showDialog<PromptWorkspaceDialogResult>(
                  context: context,
                  builder: (_) => PromptWorkspaceDialog(
                    projects: <Project>[project],
                    agentProfiles: <AgentProfile>[profile],
                    loadBranches: (_) async => <String>['main'],
                    checkBranchExists: (_, _) async => false,
                    workspaceBranches: (_) => const <String>{},
                    generateIdentity:
                        ({
                          required operationId,
                          required projectId,
                          required prompt,
                        }) async {
                          generatedPrompt = prompt;
                          return const GeneratedWorkspaceIdentity(
                            workspaceName: 'Prompt Workspace',
                            branchName: 'feat/prompt-workspace',
                          );
                        },
                    cancelGeneration: (_) async {},
                    createWorkspace:
                        ({
                          required project,
                          required sourceBranch,
                          required newBranchName,
                          required name,
                        }) async {
                          createdBranch = newBranchName;
                          createdName = name;
                          return WorkspaceCreationResult(
                            workspace: Workspace(
                              id: 'workspace-1',
                              projectId: project.id,
                              name: name,
                              branch: newBranchName,
                              sourceBranch: sourceBranch,
                              path: '/repo/alera-workspace',
                              kind: WorkspaceKind.linked,
                              status: WorkspaceStatus.active,
                              createdAt: now,
                              updatedAt: now,
                            ),
                            setupReport: WorktreeSetupReport.empty,
                          );
                        },
                    launchAgent:
                        ({
                          required workspaceId,
                          required profileId,
                          required prompt,
                        }) async {
                          launchedPrompt = prompt;
                          return const AgentProfileLaunchResult(
                            tabId: 'tab-1',
                            agentType: 'codex',
                            profileId: 'profile-1',
                          );
                        },
                  ),
                );
              },
              child: const Text('Open'),
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
    final submit = find.text('Create And Start Agent');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(generatedPrompt, 'Build workspace creation');
    expect(createdBranch, 'feat/prompt-workspace');
    expect(createdName, 'Prompt Workspace');
    expect(launchedPrompt, 'Build workspace creation');
    expect(dialogResult?.creation?.workspace.id, 'workspace-1');
    expect(dialogResult?.agentTabId, 'tab-1');
  });
}
