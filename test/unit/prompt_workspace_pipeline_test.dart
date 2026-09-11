import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );

  PromptWorkspaceCreateRequest request() => PromptWorkspaceCreateRequest(
    project: project,
    prompt: 'Build the feature',
    profileId: 'profile-1',
    sourceBranch: 'main',
  );

  test('runs identity, create, and agent launch without a dialog', () async {
    final phases = <String>[];
    final pipeline = PromptWorkspacePipeline(
      generateIdentity:
          ({required operationId, required projectId, required prompt}) async =>
              const GeneratedWorkspaceIdentity(
                workspaceName: 'Prompt Workspace',
                branchName: 'feat/prompt-workspace',
              ),
      checkBranchExists: (_, _) async => false,
      workspaceBranches: (_) => const <String>{},
      createWorkspace:
          ({
            required project,
            required sourceBranch,
            required newBranchName,
            required name,
            parentWorkspaceId,
            hostId,
          }) async {
            return WorkspaceCreationResult(
              workspace: Workspace(
                id: 'workspace-1',
                projectId: project.id,
                name: name,
                branch: newBranchName,
                path: '/repo/ws',
                createdAt: now,
                updatedAt: now,
                kind: .linked,
                status: .active,
                sourceBranch: sourceBranch,
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
          }) async => const AgentProfileLaunchResult(
            tabId: 'tab-1',
            agentType: 'codex',
            profileId: 'profile-1',
            idempotent: true,
          ),
      onPhase: phases.add,
    );

    final result = await pipeline.run(request());

    expect(result.creation.workspace.id, 'workspace-1');
    expect(result.agentTabId, 'tab-1');
    expect(phases, <String>[
      'Generating workspace identity',
      'Checking generated branch',
      'Creating workspace',
      'Starting agent',
    ]);
  });

  test('retries identity generation when the branch already exists', () async {
    var attempts = 0;
    final pipeline = PromptWorkspacePipeline(
      generateIdentity:
          ({required operationId, required projectId, required prompt}) async {
            attempts += 1;
            return GeneratedWorkspaceIdentity(
              workspaceName: 'Prompt Workspace',
              branchName: attempts == 1 ? 'feat/taken' : 'feat/available',
            );
          },
      checkBranchExists: (_, branch) async => branch == 'feat/taken',
      workspaceBranches: (_) => const <String>{},
      createWorkspace:
          ({
            required project,
            required sourceBranch,
            required newBranchName,
            required name,
            parentWorkspaceId,
            hostId,
          }) async {
            expect(newBranchName, 'feat/available');
            return WorkspaceCreationResult(
              workspace: Workspace(
                id: 'workspace-2',
                projectId: project.id,
                name: name,
                branch: newBranchName,
                path: '/repo/ws',
                createdAt: now,
                updatedAt: now,
                kind: .linked,
                status: .active,
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
          }) async => const AgentProfileLaunchResult(
            tabId: 'tab-2',
            agentType: 'codex',
            profileId: 'profile-1',
            idempotent: true,
          ),
    );

    final result = await pipeline.run(request());
    expect(attempts, 2);
    expect(result.creation.workspace.branch, 'feat/available');
  });

  test('launch failure keeps the created workspace', () async {
    final pipeline = PromptWorkspacePipeline(
      generateIdentity:
          ({required operationId, required projectId, required prompt}) async =>
              const GeneratedWorkspaceIdentity(
                workspaceName: 'Prompt Workspace',
                branchName: 'feat/prompt-workspace',
              ),
      checkBranchExists: (_, _) async => false,
      workspaceBranches: (_) => const <String>{},
      createWorkspace:
          ({
            required project,
            required sourceBranch,
            required newBranchName,
            required name,
            parentWorkspaceId,
            hostId,
          }) async {
            return WorkspaceCreationResult(
              workspace: Workspace(
                id: 'workspace-3',
                projectId: project.id,
                name: name,
                branch: newBranchName,
                path: '/repo/ws',
                createdAt: now,
                updatedAt: now,
                kind: .linked,
                status: .active,
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
            throw StateError('launch failed');
          },
    );

    await expectLater(
      pipeline.run(request()),
      throwsA(
        isA<PromptWorkspaceLaunchException>()
            .having(
              (error) => error.creation.workspace.id,
              'workspace',
              'workspace-3',
            )
            .having(
              (error) => error.toString(),
              'cause',
              contains('launch failed'),
            ),
      ),
    );
  });
}
