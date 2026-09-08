import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 7);

  group('buildAgentTaskDispatchCatalog', () {
    test('lists matching agent runs and keeps profile order', () {
      final agentTab = _tab('tab-agent');
      final shellTab = _tab('tab-shell');
      final profiles = <AgentProfile>[
        _profile('profile-1', 'Codex Builder', now),
        _profile('profile-2', 'Claude Reviewer', now, agentType: 'claude'),
      ];

      final catalog = buildAgentTaskDispatchCatalog(
        tabs: <WorkspaceTabRecord>[agentTab, shellTab],
        agentStatuses: <String, AgentStatusEntry>{
          agentTab.terminalSessionId: _entry(agentTab, .done),
        },
        profiles: profiles,
        defaultProfileId: 'profile-1',
      );

      expect(catalog.runningAgents.single.tab.id, 'tab-agent');
      expect(catalog.profiles.map((profile) => profile.id), <String>[
        'profile-1',
        'profile-2',
      ]);
      expect(catalog.defaultProfileId, 'profile-1');
      expect(catalog.isEmpty, isFalse);
    });
  });

  group('AgentTaskDispatchService', () {
    test('injects the caller prompt into a running agent tab', () async {
      final tab = _tab('tab-1');
      final workspace = _workspace();
      String? submitted;
      String? activated;
      final service = _service(
        catalog: buildAgentTaskDispatchCatalog(
          tabs: <WorkspaceTabRecord>[tab],
          agentStatuses: <String, AgentStatusEntry>{
            tab.terminalSessionId: _entry(tab, .done),
          },
          profiles: const <AgentProfile>[],
        ),
        workspace: workspace,
        tab: tab,
        onActivate: (tabId) => activated = tabId,
        onSubmit: (prompt) {
          submitted = prompt;
          return true;
        },
      );

      final result = await service.dispatch(
        const AgentTaskDispatchRequest(
          workspaceId: 'workspace-1',
          prompt: '  Fix the failing checks.  ',
        ),
        const AgentTaskDispatchRunningAgentSelection(tabId: 'tab-1'),
      );

      expect(activated, 'tab-1');
      expect(submitted, 'Fix the failing checks.');
      expect(result.openedNewTab, isFalse);
      expect(result.tabId, 'tab-1');
      expect(result.label, 'Codex');
    });

    test('launches a new tab from a profile with the caller prompt', () async {
      final workspace = _workspace();
      final profile = _profile('profile-1', 'Codex Builder', now);
      String? launchedPrompt;
      String? openedTab;
      final service = _service(
        catalog: AgentTaskDispatchCatalog(profiles: <AgentProfile>[profile]),
        workspace: workspace,
        onOpenPersisted: (tabId) => openedTab = tabId,
        onLaunch: (prompt) {
          launchedPrompt = prompt;
          return const AgentProfileLaunchResult(
            tabId: 'tab-new',
            agentType: 'codex',
            profileId: 'profile-1',
            idempotent: true,
          );
        },
      );

      final result = await service.dispatch(
        const AgentTaskDispatchRequest(
          workspaceId: 'workspace-1',
          prompt: 'Fix the failing checks.',
        ),
        const AgentTaskDispatchNewTabSelection(profileId: 'profile-1'),
      );

      expect(launchedPrompt, 'Fix the failing checks.');
      expect(openedTab, 'tab-new');
      expect(result.openedNewTab, isTrue);
      expect(result.tabId, 'tab-new');
      expect(result.profileId, 'profile-1');
      expect(result.label, 'Codex Builder');
    });

    test('reuses a binding tab when it is still present', () async {
      final tab = _tab('tab-1');
      var submits = 0;
      final service = _service(
        catalog: buildAgentTaskDispatchCatalog(
          tabs: <WorkspaceTabRecord>[tab],
          agentStatuses: <String, AgentStatusEntry>{
            tab.terminalSessionId: _entry(tab, .done),
          },
          profiles: const <AgentProfile>[],
        ),
        workspace: _workspace(),
        tab: tab,
        onSubmit: (_) {
          submits += 1;
          return true;
        },
      );

      await service.dispatchBinding(
        const AgentTaskDispatchRequest(
          workspaceId: 'workspace-1',
          prompt: 'Fix the failing checks.',
        ),
        const AgentTaskDispatchBinding(tabId: 'tab-1', profileId: 'profile-1'),
      );

      expect(submits, 1);
    });

    test('rejects an empty prompt', () async {
      final service = _service(
        catalog: const AgentTaskDispatchCatalog(),
        workspace: _workspace(),
      );
      expect(
        () => service.dispatch(
          const AgentTaskDispatchRequest(
            workspaceId: 'workspace-1',
            prompt: '   ',
          ),
          const AgentTaskDispatchNewTabSelection(profileId: 'profile-1'),
        ),
        throwsA(isA<AgentTaskDispatchException>()),
      );
    });
  });

  group('AgentType.tryParse', () {
    test('parses known adapters and ignores unknown keys', () {
      expect(AgentType.tryParse('codex'), AgentType.codex);
      expect(AgentType.tryParse('opencode2'), AgentType.opencode2);
      expect(AgentType.tryParse('unknown'), isNull);
      expect(AgentType.tryParse(null), isNull);
    });
  });
}

AgentTaskDispatchService _service({
  required AgentTaskDispatchCatalog catalog,
  required Workspace workspace,
  WorkspaceTabRecord? tab,
  void Function(String tabId)? onActivate,
  void Function(String tabId)? onOpenPersisted,
  bool Function(String prompt)? onSubmit,
  AgentProfileLaunchResult Function(String prompt)? onLaunch,
}) {
  return AgentTaskDispatchService(
    catalog: catalog,
    findWorkspace: (id) => id == workspace.id ? workspace : null,
    findTab: (workspaceId, tabId) =>
        workspaceId == workspace.id && tab?.id == tabId ? tab : null,
    activateTab: (workspaceId, tabId) async => onActivate?.call(tabId),
    openPersistedTab: (workspaceId, tabId) async =>
        onOpenPersisted?.call(tabId),
    submitPrompt: ({required workspace, required tab, required prompt}) async =>
        onSubmit?.call(prompt) ?? false,
    launchProfile:
        ({
          required workspaceId,
          required profileId,
          required prompt,
          required clientMutationId,
        }) async {
          final launch = onLaunch?.call(prompt);
          if (launch == null) {
            throw StateError('unexpected launch');
          }
          return launch;
        },
    createMutationId: () => 'mutation-1',
  );
}

Workspace _workspace() {
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Feature',
    path: '/repo/feature',
    kind: .linked,
    status: .active,
    createdAt: DateTime.utc(2026, 9, 7),
    updatedAt: DateTime.utc(2026, 9, 7),
  );
}

WorkspaceTabRecord _tab(String id) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: 'workspace-1',
    title: 'Codex',
    createdAt: DateTime.utc(2026, 9, 7),
    updatedAt: DateTime.utc(2026, 9, 7),
  );
}

AgentProfile _profile(
  String id,
  String name,
  DateTime now, {
  String agentType = 'codex',
}) {
  return AgentProfile(
    id: id,
    name: name,
    agentType: agentType,
    command: agentType,
    createdAt: now,
    updatedAt: now,
  );
}

AgentStatusEntry _entry(WorkspaceTabRecord tab, AgentStatusState state) {
  final now = DateTime.utc(2026, 9, 7);
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: .codex,
    state: state,
    prompt: '',
    updatedAt: now,
    stateStartedAt: now,
  );
}
