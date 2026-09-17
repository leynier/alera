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

  group('agentTaskDispatchShouldActivate', () {
    test('focuses only a user-initiated send on the visible workspace', () {
      expect(
        agentTaskDispatchShouldActivate(
          activate: true,
          workspaceId: 'workspace-1',
          activeWorkspaceId: 'workspace-1',
        ),
        isTrue,
      );
      expect(
        agentTaskDispatchShouldActivate(
          activate: true,
          workspaceId: 'workspace-1',
          activeWorkspaceId: 'workspace-2',
        ),
        isFalse,
      );
      expect(
        agentTaskDispatchShouldActivate(
          activate: false,
          workspaceId: 'workspace-1',
          activeWorkspaceId: 'workspace-1',
        ),
        isFalse,
      );
    });
  });

  group('AgentTaskDispatchService focus', () {
    test(
      'user-initiated dispatchBinding activates the current workspace tab',
      () async {
        final tab = _tab('tab-1');
        String? activated;
        final service = _service(
          catalog: _runningCatalog(tab),
          tab: tab,
          onActivate: (tabId) => activated = tabId,
          onSubmit: (_) => true,
        );

        await service.dispatchBinding(
          const AgentTaskDispatchRequest(
            workspaceId: 'workspace-1',
            prompt: 'Fix the failing checks.',
          ),
          const AgentTaskDispatchBinding(tabId: 'tab-1'),
        );

        expect(activated, 'tab-1');
      },
    );

    test(
      'dispatchBinding does not activate when another workspace is visible',
      () async {
        final tab = _tab('tab-1');
        var activated = false;
        var submits = 0;
        final service = _service(
          catalog: _runningCatalog(tab),
          tab: tab,
          activeWorkspaceId: () => 'workspace-other',
          onActivate: (_) => activated = true,
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
          const AgentTaskDispatchBinding(tabId: 'tab-1'),
        );

        expect(submits, 1);
        expect(activated, isFalse);
      },
    );

    test('watch follow-up dispatchBinding does not activate on the current workspace', () async {
      final tab = _tab('tab-1');
      var activated = false;
      var submits = 0;
      final service = _service(
        catalog: _runningCatalog(tab),
        tab: tab,
        onActivate: (_) => activated = true,
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
        const AgentTaskDispatchBinding(tabId: 'tab-1'),
        activate: false,
      );

      expect(submits, 1);
      expect(activated, isFalse);
    });

    test(
      'watch follow-up persists a new profile tab without activating',
      () async {
        final profile = _profile('profile-1', now);
        var openedActivate = true;
        String? openedTab;
        final service = _service(
          catalog: AgentTaskDispatchCatalog(profiles: <AgentProfile>[profile]),
          onOpenPersisted: (tabId, {required bool activate}) {
            openedTab = tabId;
            openedActivate = activate;
          },
          onLaunch: (_) {
            return const AgentProfileLaunchResult(
              tabId: 'tab-new',
              agentType: 'codex',
              profileId: 'profile-1',
              idempotent: true,
            );
          },
        );

        final result = await service.dispatchBinding(
          const AgentTaskDispatchRequest(
            workspaceId: 'workspace-1',
            prompt: 'Fix the failing checks.',
          ),
          const AgentTaskDispatchBinding(profileId: 'profile-1'),
          activate: false,
        );

        expect(openedTab, 'tab-new');
        expect(openedActivate, isFalse);
        expect(result.openedNewTab, isTrue);
      },
    );

    test(
      'user-initiated new tab does not activate after leaving the workspace',
      () async {
        final profile = _profile('profile-1', now);
        var openedActivate = true;
        final service = _service(
          catalog: AgentTaskDispatchCatalog(profiles: <AgentProfile>[profile]),
          activeWorkspaceId: () => 'workspace-other',
          onOpenPersisted: (_, {required bool activate}) {
            openedActivate = activate;
          },
          onLaunch: (_) {
            return const AgentProfileLaunchResult(
              tabId: 'tab-new',
              agentType: 'codex',
              profileId: 'profile-1',
              idempotent: true,
            );
          },
        );

        await service.dispatch(
          const AgentTaskDispatchRequest(
            workspaceId: 'workspace-1',
            prompt: 'Fix the failing checks.',
          ),
          const AgentTaskDispatchNewTabSelection(profileId: 'profile-1'),
        );

        expect(openedActivate, isFalse);
      },
    );
  });
}

AgentTaskDispatchCatalog _runningCatalog(WorkspaceTabRecord tab) {
  return buildAgentTaskDispatchCatalog(
    tabs: <WorkspaceTabRecord>[tab],
    agentStatuses: <String, AgentStatusEntry>{
      tab.terminalSessionId: _entry(tab),
    },
    profiles: const <AgentProfile>[],
  );
}

AgentTaskDispatchService _service({
  required AgentTaskDispatchCatalog catalog,
  WorkspaceTabRecord? tab,
  String? Function()? activeWorkspaceId,
  void Function(String tabId)? onActivate,
  void Function(String tabId, {required bool activate})? onOpenPersisted,
  bool Function(String prompt)? onSubmit,
  AgentProfileLaunchResult Function(String prompt)? onLaunch,
}) {
  final workspace = _workspace();
  return AgentTaskDispatchService(
    catalog: catalog,
    findWorkspace: (id) => id == workspace.id ? workspace : null,
    findTab: (workspaceId, tabId) =>
        workspaceId == workspace.id && tab?.id == tabId ? tab : null,
    activeWorkspaceId: activeWorkspaceId ?? () => workspace.id,
    activateTab: (workspaceId, tabId) async => onActivate?.call(tabId),
    openPersistedTab: (workspaceId, tabId, {bool activate = true}) async =>
        onOpenPersisted?.call(tabId, activate: activate),
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

AgentProfile _profile(String id, DateTime now) {
  return AgentProfile(
    id: id,
    name: 'Codex Builder',
    agentType: 'codex',
    command: 'codex',
    createdAt: now,
    updatedAt: now,
  );
}

AgentStatusEntry _entry(WorkspaceTabRecord tab) {
  final now = DateTime.utc(2026, 9, 7);
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: .codex,
    state: .done,
    prompt: '',
    updatedAt: now,
    stateStartedAt: now,
  );
}
