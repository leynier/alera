part of 'runtime_repositories_test.dart';

void _registerRuntimeStateMigrationTests() {
  test('RuntimeStateMigration seeds legacy state once', () async {
    final client = _FakeRuntimeHostClient();
    final legacySettings = _MemorySettingsRepository()
      ..settings = AleraSettings.defaults.copyWith(
        aiAssist: const AiAssistSettings(
          agent: .chatgpt,
          selectedThinkingByModel: <String, String>{'gpt-6.1-sol': 'high'},
          selectedThinkingByOperation: <AiAssistOperation, Map<String, String>>{
            AiAssistOperation.commitMessage: <String, String>{
              'gpt-6.1-sol': 'xhigh',
            },
          },
          promptSettingsByOperation:
              <AiAssistOperation, AiAssistPromptSettings>{
                AiAssistOperation.commitMessage: AiAssistPromptSettings(
                  agent: .chatgpt,
                  model: 'gpt-6.1-sol',
                ),
              },
          chatGptServiceTier: aiAssistChatGptFastServiceTier,
        ),
      );
    final legacyProjects = _MemoryProjectRepository()
      ..projects.add(_project(id: 'project-1', name: 'Legacy'));
    final legacyWorkbench = _MemoryWorkbenchRepository();
    final workspace = _workspace(id: 'workspace-1', projectId: 'project-1');
    legacyWorkbench.workspaces[workspace.id] = workspace;
    legacyWorkbench.tabs['tab-1'] = WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: workspace.id,
      title: 'Terminal',
      createdAt: _timestamp,
      updatedAt: _timestamp,
    );
    legacyWorkbench.layouts[workspace.id] = WorkbenchLayout.single(
      workspaceId: workspace.id,
      tabIds: const <String>['tab-1'],
    );
    final runtimeProjects = _MemoryProjectRepository();
    final runtimeWorkbench = _MemoryWorkbenchRepository();
    var legacyFactoryCalls = 0;
    final migration = RuntimeStateMigration(
      runtimeClient: client,
      legacyRepositories: () async {
        legacyFactoryCalls += 1;
        return RuntimeStateLegacyRepositories(
          projectRepository: legacyProjects,
          projectConfigRepository: _MemoryProjectConfigRepository(),
          settingsRepository: legacySettings,
          workbenchRepository: legacyWorkbench,
        );
      },
      runtimeProjects: runtimeProjects,
      runtimeWorkbench: runtimeWorkbench,
    );

    await migration.ensureMigrated();
    await migration.ensureMigrated();

    expect(legacyFactoryCalls, 1);
    expect(runtimeProjects.projects.single.name, 'Legacy');
    expect(runtimeWorkbench.workspaces[workspace.id], workspace);
    expect(runtimeWorkbench.tabs['tab-1']?.workspaceId, workspace.id);
    expect(runtimeWorkbench.layouts[workspace.id], isNotNull);
    expect(client.requests, hasLength(18));
    expect(
      client.requests.where((request) => request == 'runtimeSettings.update'),
      hasLength(4),
    );
    final aiAssistPayload = client.payloads['runtimeSettings.update']!
        .map((payload) => payload['aiTextGeneration'])
        .whereType<Map<String, Object?>>()
        .single;
    expect(aiAssistPayload['selectedThinkingByModel'], <String, String>{
      'gpt-6.1-sol': 'high',
    });
    expect(aiAssistPayload['selectedThinkingByOperation'], <String, Object?>{
      'commitMessage': <String, String>{'gpt-6.1-sol': 'xhigh'},
    });
    expect(aiAssistPayload['promptSettingsByOperation'], <String, Object?>{
      'commitMessage': <String, Object?>{
        'agent': 'chatgpt',
        'model': 'gpt-6.1-sol',
      },
    });
    expect(
      aiAssistPayload['chatGptServiceTier'],
      aiAssistChatGptFastServiceTier,
    );
  });
}
