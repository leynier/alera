part of 'app_providers_test.dart';

/// Coordinator behaviour that turns agent status changes into desktop
/// notifications: which states notify, the repeat cooldown, and activation.
void _registerAgentNotificationCoordinatorTests() {
  group('agent notification coordinator', () {
    test(
      'notification coordinator emits native notifications for done states',
      () async {
        final presenter = _FakeNotificationPresenter();
        final settings = AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(codex: true),
            agentStatusNotificationsEnabled: true,
            agentStatusFinishedNotificationsEnabled: true,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(settings),
            agentStatusNotificationPresenterProvider.overrideWithValue(
              presenter,
            ),
            ..._immediateNotificationDelivery,
          ],
        );
        addTearDown(container.dispose);

        container.read(agentStatusNotificationCoordinatorProvider);
        container
            .read(agentStatusControllerProvider.notifier)
            .applyHookEvent(
              const AgentHookEvent(
                terminalSessionId: 'session-1',
                workspaceId: 'workspace-1',
                tabId: 'tab-1',
                agentType: AgentType.codex,
                hookEventName: 'Stop',
                payload: <String, Object?>{'prompt': 'Run tests'},
              ),
            );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(presenter.initializeCalls, 1);
        expect(presenter.notifications, hasLength(1));
        expect(presenter.notifications.single.title, 'Codex finished');
        expect(presenter.notifications.single.body, 'Open Alera');
      },
    );

    test(
      'notification coordinator stays quiet on finished turns by default',
      () async {
        final presenter = _FakeNotificationPresenter();
        final settings = AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(codex: true),
            agentStatusNotificationsEnabled: true,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(settings),
            agentStatusNotificationPresenterProvider.overrideWithValue(
              presenter,
            ),
            ..._immediateNotificationDelivery,
          ],
        );
        addTearDown(container.dispose);

        container.read(agentStatusNotificationCoordinatorProvider);
        final statuses = container.read(agentStatusControllerProvider.notifier);
        statuses.applyHookEvent(
          const AgentHookEvent(
            terminalSessionId: 'session-1',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
            agentType: AgentType.codex,
            hookEventName: 'Stop',
            payload: <String, Object?>{'prompt': 'Run tests'},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(presenter.notifications, isEmpty);

        statuses.applyHookEvent(
          const AgentHookEvent(
            terminalSessionId: 'session-1',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
            agentType: AgentType.codex,
            hookEventName: 'PermissionRequest',
            payload: <String, Object?>{'prompt': 'Run tests'},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(presenter.notifications, hasLength(1));
        expect(presenter.notifications.single.title, 'Codex needs attention');
      },
    );

    test(
      'notification coordinator keeps its cooldown across settings changes',
      () async {
        final presenter = _FakeNotificationPresenter();
        final settings = _TestSettingsController(
          AleraSettings.defaults.copyWith(
            agents: AleraSettings.defaults.agents.copyWith(
              agentStatusHooks: const AgentStatusHookSettings(codex: true),
              agentStatusNotificationsEnabled: true,
            ),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWith(() => settings),
            agentStatusNotificationPresenterProvider.overrideWithValue(
              presenter,
            ),
            ..._immediateNotificationDelivery,
          ],
        );
        addTearDown(container.dispose);

        container.read(agentStatusNotificationCoordinatorProvider);
        final statuses = container.read(agentStatusControllerProvider.notifier);
        void requestPermission() {
          statuses.applyHookEvent(
            const AgentHookEvent(
              terminalSessionId: 'session-1',
              workspaceId: 'workspace-1',
              tabId: 'tab-1',
              agentType: AgentType.codex,
              hookEventName: 'PermissionRequest',
              payload: <String, Object?>{'prompt': 'Run tests'},
            ),
          );
        }

        requestPermission();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(presenter.notifications, hasLength(1));

        // Toggling a hook used to rebuild the coordinator, which dropped the
        // delivery history and let the very next repeat notify again.
        settings.setState(
          settings.state.copyWith(
            agents: settings.state.agents.copyWith(
              agentStatusHooks: const AgentStatusHookSettings(
                codex: true,
                claude: true,
              ),
            ),
          ),
        );
        statuses.applyHookEvent(
          const AgentHookEvent(
            terminalSessionId: 'session-1',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
            agentType: AgentType.codex,
            hookEventName: 'PostToolUse',
            payload: <String, Object?>{'prompt': 'Run tests'},
          ),
        );
        requestPermission();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(presenter.notifications, hasLength(1));
      },
    );

    test(
      'notification coordinator composes workspace context and activation payloads',
      () async {
        final presenter = _FakeNotificationPresenter();
        final windowActivator = _FakeNotificationWindowActivator();
        final now = DateTime.utc(2026, 5, 26, 10);
        final project = _project(id: 'project-1', path: '/repo/alera');
        final workspace = Workspace(
          id: 'workspace-1',
          projectId: project.id,
          name: 'Main',
          branch: 'main',
          path: project.repoPath,
          createdAt: now,
          updatedAt: now,
          kind: WorkspaceKind.main,
          status: WorkspaceStatus.active,
        );
        final tab = WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: workspace.id,
          title: 'Terminal 1',
          createdAt: now,
          updatedAt: now,
        );
        final controller = _TestWorkbenchController(
          WorkbenchState(
            projects: <Project>[project],
            workspacesByProject: <String, List<Workspace>>{
              project.id: <Workspace>[workspace],
            },
            tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
              workspace.id: <WorkspaceTabRecord>[tab],
            },
            bootstrapped: true,
          ),
        );
        final runtime = _FocusableTerminalRuntime();
        final settings = AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(codex: true),
            agentStatusNotificationsEnabled: true,
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(settings),
            agentStatusNotificationPresenterProvider.overrideWithValue(
              presenter,
            ),
            agentStatusNotificationWindowActivatorProvider.overrideWithValue(
              windowActivator,
            ),
            workbenchControllerProvider.overrideWith(() => controller),
            terminalRuntimeProvider.overrideWith((ref) => runtime),
            ..._immediateNotificationDelivery,
          ],
        );
        addTearDown(() {
          runtime.dispose();
          container.dispose();
        });

        container.read(agentStatusNotificationCoordinatorProvider);
        container
            .read(agentStatusControllerProvider.notifier)
            .applyHookEvent(
              const AgentHookEvent(
                terminalSessionId: 'session-1',
                workspaceId: 'workspace-1',
                tabId: 'tab-1',
                agentType: AgentType.codex,
                hookEventName: 'PermissionRequest',
                payload: <String, Object?>{'prompt': 'Run tests'},
              ),
            );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(presenter.notifications, hasLength(1));
        expect(presenter.notifications.single.body, 'Workspace Main in Alera');

        presenter.onSelected!(presenter.notifications.single.payload);
        await Future<void>.delayed(Duration.zero);

        expect(windowActivator.calls, 1);
        expect(controller.selectedWorkspaceIds, <String>['workspace-1']);
        expect(controller.activeTabs, <String, String>{'workspace-1': 'tab-1'});
        expect(runtime.focusedTabIds, <String>['tab-1']);
      },
    );
  });
}
