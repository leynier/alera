import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

class _SectionFakeClient extends FakeTerminalClient
    implements MobileWorkspaceSectionClient {
  final List<String> sectionAssignments = <String>[];
  bool failSectionAssignment = false;

  @override
  bool get supportsWorkspaceSections => true;

  @override
  Future<List<WorkspaceSectionSummary>> listWorkspaceSections() async =>
      const <WorkspaceSectionSummary>[];

  @override
  Future<WorkspaceSectionSummary> createWorkspaceSection(
    String name,
    String workspaceId,
  ) async => throw UnimplementedError();

  @override
  Future<void> setWorkspaceSection(
    String workspaceId,
    String? sectionId,
  ) async {
    if (failSectionAssignment) {
      throw StateError('Section no longer exists');
    }
    sectionAssignments.add('$workspaceId $sectionId');
  }

  @override
  Future<void> removeWorkspaceSection(String sectionId) async {}
}

void main() {
  test('assigns the generated section after creation', () async {
    final client = _SectionFakeClient()
      ..projectBranches = const <String>['main']
      ..generatedWorkspaceIdentity = const GeneratedWorkspaceIdentity(
        workspaceName: 'Generated Workspace',
        branchName: 'feat/generated-workspace',
        sectionId: 'section-1',
      );
    addTearDown(client.dispose);
    final outcome = await runPromptWorkspaceCreate(
      client: client,
      loadTerminalClient: () async => client,
      request: const PromptWorkspaceCreateRequest(
        hostId: 'host',
        projectId: 'project',
        prompt: 'Build the feature',
        sourceBranch: 'main',
        profileId: 'profile-1',
        workspaceBranches: {},
        autoAssignSection: true,
      ),
      clientMutationId: 'section-test',
    );

    expect(client.lastGenerateWorkspaceIdentityAutoAssign, isTrue);
    expect(client.sectionAssignments, <String>['created section-1']);
    expect(outcome.creation.workspace.id, 'created');
  });

  test('a section assignment failure does not fail the flow', () async {
    final client = _SectionFakeClient()
      ..projectBranches = const <String>['main']
      ..failSectionAssignment = true
      ..generatedWorkspaceIdentity = const GeneratedWorkspaceIdentity(
        workspaceName: 'Generated Workspace',
        branchName: 'feat/generated-workspace',
        sectionId: 'section-1',
      );
    addTearDown(client.dispose);
    final outcome = await runPromptWorkspaceCreate(
      client: client,
      loadTerminalClient: () async => client,
      request: const PromptWorkspaceCreateRequest(
        hostId: 'host',
        projectId: 'project',
        prompt: 'Build the feature',
        sourceBranch: 'main',
        profileId: 'profile-1',
        workspaceBranches: {},
        autoAssignSection: true,
      ),
      clientMutationId: 'section-failure-test',
    );

    expect(client.sectionAssignments, isEmpty);
    expect(outcome.creation.workspace.id, 'created');
    expect(outcome.agentTabId, 'agent-tab');
  });
}
