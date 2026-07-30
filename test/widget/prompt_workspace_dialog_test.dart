import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/presentation/prompt_workspace_dialog.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
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
    String? createdParentWorkspaceId;
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
                    parentWorkspaces: const <Workspace>[],
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
                          parentWorkspaceId,
                        }) async {
                          createdBranch = newBranchName;
                          createdName = name;
                          createdParentWorkspaceId = parentWorkspaceId;
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
    expect(createdParentWorkspaceId, isNull);
    expect(launchedPrompt, 'Build workspace creation');
    expect(dialogResult?.creation?.workspace.id, 'workspace-1');
    expect(dialogResult?.agentTabId, 'tab-1');
  });

  testWidgets(
    'defaults the parent to the selected project main workspace and allows changing it',
    (tester) async {
      final now = DateTime.utc(2026, 7, 30);
      final alera = Project(
        id: 'project-alera',
        name: 'Alera',
        repoPath: '/repo/alera',
        createdAt: now,
        updatedAt: now,
      );
      final orca = Project(
        id: 'project-orca',
        name: 'Orca',
        repoPath: '/repo/orca',
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
      final aleraMain = _workspace(
        id: 'alera-main',
        projectId: alera.id,
        name: 'Alera',
        branch: 'main',
        kind: WorkspaceKind.main,
        now: now,
      );
      final orcaMain = _workspace(
        id: 'orca-main',
        projectId: orca.id,
        name: 'Orca',
        branch: 'main',
        kind: WorkspaceKind.main,
        now: now,
      );
      final orcaFeature = _workspace(
        id: 'orca-feature',
        projectId: orca.id,
        name: 'Feature Workspace',
        branch: 'feat/other',
        kind: WorkspaceKind.linked,
        now: now,
      );
      String? createdParentWorkspaceId;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () {
                  showDialog<PromptWorkspaceDialogResult>(
                    context: context,
                    builder: (_) => PromptWorkspaceDialog(
                      projects: <Project>[orca, alera],
                      agentProfiles: <AgentProfile>[profile],
                      loadBranches: (_) async => <String>['main'],
                      checkBranchExists: (_, _) async => false,
                      workspaceBranches: (_) => const <String>{},
                      parentWorkspaces: <Workspace>[
                        aleraMain,
                        orcaMain,
                        orcaFeature,
                      ],
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
                          }) async {
                            createdParentWorkspaceId = parentWorkspaceId;
                            return WorkspaceCreationResult(
                              workspace: _workspace(
                                id: 'created',
                                projectId: project.id,
                                name: name,
                                branch: newBranchName,
                                kind: WorkspaceKind.linked,
                                now: now,
                              ),
                              setupReport: WorktreeSetupReport.empty,
                            );
                          },
                      launchAgent:
                          ({
                            required workspaceId,
                            required profileId,
                            required prompt,
                          }) async => const AgentProfileLaunchResult(
                            tabId: 'tab-1',
                            agentType: 'codex',
                            profileId: 'profile-1',
                          ),
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

      AleraDropdownField<String?> parentField() {
        return tester.widget<AleraDropdownField<String?>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AleraDropdownField<String?> &&
                widget.labelText == 'Parent Workspace',
          ),
        );
      }

      expect(parentField().value, aleraMain.id);
      final projectField = tester.widget<AleraDropdownField<Project>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AleraDropdownField<Project> &&
              widget.labelText == 'Project',
        ),
      );
      expect(projectField.entries.map((entry) => entry.value.id), <String>[
        alera.id,
        orca.id,
      ]);
      projectField.onChanged(orca);
      await tester.pumpAndSettle();

      expect(parentField().value, orcaMain.id);
      expect(parentField().entries.map((entry) => entry.value), <String?>[
        null,
        orcaMain.id,
        orcaFeature.id,
        aleraMain.id,
      ]);

      parentField().onChanged(orcaFeature.id);
      await tester.pump();
      expect(parentField().value, orcaFeature.id);

      parentField().onChanged(null);
      await tester.pump();
      expect(parentField().value, isNull);

      parentField().onChanged(orcaFeature.id);
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Initial Prompt'),
        'Build another workspace',
      );
      final submit = find.text('Create And Start Agent');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(createdParentWorkspaceId, orcaFeature.id);
    },
  );
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
    status: WorkspaceStatus.active,
    createdAt: now,
    updatedAt: now,
  );
}
