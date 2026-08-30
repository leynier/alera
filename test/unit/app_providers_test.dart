import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/application/terminal_host_settings_config.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_awake_assertions.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_request_parser.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_receiver.dart';
import 'package:alera/src/features/agent_status/infra/agent_runtime_overlay_service.dart';
import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/codex_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/desktop_agent_status_notification_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/agent_status/infra/window_manager_agent_window_activator.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fake_git_backend.dart';
import 'fake_project_config.dart';

part 'app_providers_notification_test_cases.dart';
part 'app_providers_test_harness.dart';
part 'app_providers_terminal_fakes.dart';
part 'app_providers_wrapper_path_test_cases.dart';

void main() {
  _registerAgentNotificationCoordinatorTests();
  group('app providers', () {
    test(
      'workspaceServiceProvider uses the configured workspace root override',
      () async {
        final gitBackend = FakeGitBackend()..sourceBranches = <String>['main'];
        final repository = _FakeWorkbenchRepository();
        final repoDir = Directory.systemTemp.createTempSync(
          'alera-provider-repo',
        );
        final repoPath = repoDir.path;
        addTearDown(() => repoDir.deleteSync(recursive: true));

        final project = _project(id: 'project-1', path: repoPath);
        final workspaceRoot = Directory.systemTemp
            .createTempSync('alera-provider-root')
            .path;
        addTearDown(() => Directory(workspaceRoot).deleteSync(recursive: true));

        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(
              AleraSettings.defaults.copyWith(
                general: AleraSettings.defaults.general.copyWith(
                  workspaceDirectory: workspaceRoot,
                ),
              ),
            ),
            workbenchRepositoryProvider.overrideWithValue(repository),
            gitBackendProvider.overrideWithValue(gitBackend),
            projectServiceProvider.overrideWithValue(
              ProjectService(gitBackend),
            ),
            projectConfigServiceProvider.overrideWithValue(
              ProjectConfigService(
                repository: FakeProjectConfigRepository(),
                fileStore: FakeProjectConfigFileStore(),
              ),
            ),
            managedWorkspaceRuntimeProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(workspaceServiceProvider);
        final workspace = (await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/coverage',
        )).workspace;

        expect(
          workspace.path,
          p.join(
            workspaceRoot,
            '${_slugSegment(p.basename(repoPath))}-project-1',
            'feature-coverage',
          ),
        );
        expect(repository.workspaces.single.path, workspace.path);
        expect(
          gitBackend.calls.any(
            (call) =>
                call.method == 'createWorktree' &&
                call.args['repoPath'] == repoPath &&
                call.args['path'] == workspace.path,
          ),
          isTrue,
        );
      },
    );

    test(
      'terminalRuntimeProvider listens to terminal settings changes',
      () async {
        final settingsController = _TestSettingsController(
          AleraSettings.defaults,
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWith(() => settingsController),
            externalUriLauncherProvider.overrideWithValue(
              _FakeExternalUriLauncher(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final runtime = container.read(terminalRuntimeProvider);
        final updatedTerminal = settingsController.state.terminal.copyWith(
          fontSize: settingsController.state.terminal.fontSize + 1,
        );

        settingsController.setState(
          settingsController.state.copyWith(terminal: updatedTerminal),
        );
        await Future<void>.delayed(Duration.zero);

        expect(container.read(terminalRuntimeProvider), same(runtime));
      },
    );

    test(
      'terminalRuntimeProvider leaves agent hook launch environments to host',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final root = await Directory.systemTemp.createTemp(
          'alera-provider-terminal-runtime-',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        final support = Directory(p.join(root.path, 'support'))
          ..createSync(recursive: true);
        final receiver = AgentHookReceiver(
          statusSink: _FakeStatusSink(),
          applicationSupportDirectory: () async => support,
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(receiver.dispose);
        final client = _FakeTerminalHostClient();
        final now = DateTime.utc(2026, 5, 28);
        final workspace = Workspace(
          id: 'workspace-1',
          projectId: 'project-1',
          name: 'Main',
          branch: 'main',
          path: home.path,
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
        final disabledClient = _FakeTerminalHostClient();
        final disabledContainer = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(
              AleraSettings.defaults,
            ),
            terminalHostClientProvider.overrideWithValue(disabledClient),
            externalUriLauncherProvider.overrideWithValue(
              _FakeExternalUriLauncher(),
            ),
          ],
        );
        addTearDown(disabledContainer.dispose);

        final disabledRuntime = disabledContainer.read(terminalRuntimeProvider);
        await disabledRuntime
            .sessionFor(workspace: workspace, tab: tab)
            .ensureStarted();
        expect(
          disabledClient.launches.single.environment,
          isNot(contains('ALERA_TERMINAL_SESSION_ID')),
        );
        disabledRuntime.dispose();

        final settings = AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(copilot: true),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(settings),
            terminalHostClientProvider.overrideWithValue(client),
            externalUriLauncherProvider.overrideWithValue(
              _FakeExternalUriLauncher(),
            ),
            agentHookReceiverProvider.overrideWithValue(receiver),
            codexRuntimeHomeServiceProvider.overrideWithValue(
              CodexRuntimeHomeService(
                homeDirectory: home.path,
                applicationSupportDirectory: () async => support,
                platform: ManagedAgentHookPlatform.posix,
                environment: <String, String>{'HOME': home.path},
              ),
            ),
            claudeRuntimeHomeServiceProvider.overrideWithValue(
              ClaudeRuntimeHomeService(
                homeDirectory: home.path,
                applicationSupportDirectory: () async => support,
                platform: ManagedAgentHookPlatform.posix,
                environment: <String, String>{'HOME': home.path},
                syncMacOSKeychainCredentials: false,
              ),
            ),
            agentRuntimeOverlayServiceProvider.overrideWithValue(
              AgentRuntimeOverlayService(
                homeDirectory: home.path,
                platform: ManagedAgentHookPlatform.posix,
                environment: <String, String>{
                  'HOME': home.path,
                  'SHELL': '/bin/zsh',
                },
                applicationSupportDirectory: () async => support,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final runtime = container.read(terminalRuntimeProvider);
        final session = runtime.sessionFor(workspace: workspace, tab: tab);
        await session.ensureStarted();

        expect(
          client.launches.single.environment,
          isNot(contains('ALERA_TERMINAL_SESSION_ID')),
        );
        runtime.dispose();
      },
    );

    test('terminalHostWarmupCoordinatorProvider starts the host with settings config', () async {
      final client = _FakeTerminalHostClient();
      final settings = AleraSettings.defaults.copyWith(
        terminal: AleraSettings.defaults.terminal.copyWith(
          hostEmptyShutdownDelaySeconds: 7,
          hostDetachedSessionShutdownDelaySeconds: 14,
          hostScrollbackBytes: 4096,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWithValue(settings),
          terminalHostClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      container.read(terminalHostWarmupCoordinatorProvider);
      await Future<void>.delayed(Duration.zero);

      // What the mapping produces is terminal_host_settings_config_test's
      // job; this only checks the warmup sends it.
      expect(client.ensureStartedConfigs.map((c) => c.toJson()), <Object?>[
        terminalHostConfigFor(settings.terminal).toJson(),
      ]);
    });

    test('agent awake coordinator follows working agent statuses', () async {
      final displayLock = _FakeAwakeDisplayLock();
      final assertion = _FakeAwakeAssertion();
      final settings = AleraSettings.defaults.copyWith(
        agents: AleraSettings.defaults.agents.copyWith(
          agentStatusHooks: const AgentStatusHookSettings(codex: true),
          keepComputerAwakeWhileAgentsWork: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWithValue(settings),
          agentAwakeDisplayLockProvider.overrideWithValue(displayLock),
          agentAwakeAssertionsProvider.overrideWithValue(<AgentAwakeAssertion>[
            assertion,
          ]),
        ],
      );
      addTearDown(container.dispose);

      container.read(agentAwakeCoordinatorProvider);
      container
          .read(agentStatusControllerProvider.notifier)
          .applyHookEvent(
            const AgentHookEvent(
              terminalSessionId: 'session-1',
              workspaceId: 'workspace-1',
              tabId: 'tab-1',
              agentType: AgentType.codex,
              hookEventName: 'UserPromptSubmit',
              payload: <String, Object?>{'prompt': 'Run tests'},
            ),
          );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(displayLock.states, <bool>[true]);
      expect(assertion.starts, isNotEmpty);

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

      expect(displayLock.states, <bool>[true, false]);
      expect(assertion.stops, isNotEmpty);
    });

    test('agent awake service reacts to settings listener changes', () async {
      final displayLock = _FakeAwakeDisplayLock();
      final assertion = _FakeAwakeAssertion();
      final settingsController = _TestSettingsController(
        AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(codex: true),
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWith(() => settingsController),
          agentAwakeDisplayLockProvider.overrideWithValue(displayLock),
          agentAwakeAssertionsProvider.overrideWithValue(<AgentAwakeAssertion>[
            assertion,
          ]),
        ],
      );
      addTearDown(container.dispose);

      container.read(agentAwakeServiceProvider);
      settingsController.setState(
        settingsController.state.copyWith(
          agents: settingsController.state.agents.copyWith(
            keepComputerAwakeWhileAgentsWork: true,
          ),
        ),
      );
      container
          .read(agentStatusControllerProvider.notifier)
          .applyHookEvent(
            const AgentHookEvent(
              terminalSessionId: 'session-1',
              workspaceId: 'workspace-1',
              tabId: 'tab-1',
              agentType: AgentType.codex,
              hookEventName: 'UserPromptSubmit',
              payload: <String, Object?>{'prompt': 'Run tests'},
            ),
          );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(displayLock.states, contains(true));
      expect(assertion.starts, isNotEmpty);

      settingsController.setState(
        settingsController.state.copyWith(
          agents: settingsController.state.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(displayLock.states.last, isFalse);
      expect(assertion.stops, isNotEmpty);
    });

    test('agent awake assertions include Windows system sleep lock', () {
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWithValue(AleraSettings.defaults),
          processRunnerProvider.overrideWithValue(_FakeProcessRunner()),
        ],
      );
      addTearDown(container.dispose);

      final assertions = container.read(agentAwakeAssertionsProvider);

      expect(assertions, contains(isA<MacosSystemSleepAssertion>()));
      expect(assertions, contains(isA<LinuxLidSleepAssertion>()));
      expect(assertions, contains(isA<WindowsSystemSleepAssertion>()));
    });

    test('agent status default providers instantiate concrete services', () {
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWithValue(AleraSettings.defaults),
          processRunnerProvider.overrideWithValue(_FakeProcessRunner()),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(agentHookReceiverProvider),
        isA<AgentHookReceiver>(),
      );
      expect(
        container.read(managedAgentHookInstallServiceProvider),
        isA<ManagedAgentHookInstallService>(),
      );
      expect(
        container.read(codexRuntimeHomeServiceProvider),
        isA<CodexRuntimeHomeService>(),
      );
      expect(
        container.read(claudeRuntimeHomeServiceProvider),
        isA<ClaudeRuntimeHomeService>(),
      );
      expect(
        container.read(agentRuntimeOverlayServiceProvider),
        isA<AgentRuntimeOverlayService>(),
      );
      expect(
        container.read(agentStatusNotificationPresenterProvider),
        isA<DesktopAgentStatusNotificationService>(),
      );
      expect(
        container.read(agentStatusNotificationWindowActivatorProvider),
        isA<WindowManagerAgentWindowActivator>(),
      );
      expect(
        container.read(agentStatusNotificationActivationServiceProvider),
        isA<AgentStatusNotificationActivationService>(),
      );
      expect(
        container.read(agentAwakeDisplayLockProvider),
        isA<AgentAwakeDisplayLock>(),
      );
      expect(
        container.read(agentAwakeServiceProvider),
        isA<AgentAwakeService>(),
      );
      container.read(agentAwakeCoordinatorProvider);
    });

    test('agent hook receiver provider filters disabled agents', () async {
      final support = await Directory.systemTemp.createTemp(
        'alera-provider-hook-receiver-',
      );
      addTearDown(() async {
        if (await support.exists()) {
          await support.delete(recursive: true);
        }
      });
      final previousPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(support.path);
      addTearDown(() => PathProviderPlatform.instance = previousPlatform);
      final settings = AleraSettings.defaults.copyWith(
        agents: AleraSettings.defaults.agents.copyWith(
          agentStatusHooks: const AgentStatusHookSettings(codex: true),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWithValue(settings),
          agentHookServerProvider.overrideWithValue(_FakeAgentHookServer()),
        ],
      );
      addTearDown(container.dispose);

      final receiver = container.read(agentHookReceiverProvider);
      await receiver.start();

      final codexResponse = await _postHook(
        receiver.endpoint!.port,
        path: '/hook/codex',
        token: receiver.endpoint!.token,
        body: jsonEncode(<String, Object?>{
          'terminalSessionId': 'session-1',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'hookEventName': 'UserPromptSubmit',
          'payload': <String, Object?>{'prompt': 'ship it'},
        }),
      );
      final copilotResponse = await _postHook(
        receiver.endpoint!.port,
        path: '/hook/copilot',
        token: receiver.endpoint!.token,
        body: jsonEncode(<String, Object?>{
          'terminalSessionId': 'session-2',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-2',
          'hookEventName': 'UserPromptSubmit',
          'payload': <String, Object?>{'prompt': 'skip it'},
        }),
      );

      expect(codexResponse.statusCode, HttpStatus.noContent);
      expect(copilotResponse.statusCode, HttpStatus.noContent);
      expect(
        container.read(agentStatusControllerProvider).containsKey('session-1'),
        isTrue,
      );
      expect(
        container.read(agentStatusControllerProvider).containsKey('session-2'),
        isFalse,
      );
    });

    test(
      'agent hook receiver lifecycle coordinator starts enabled hooks',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'alera-provider-hook-lifecycle-',
        );
        addTearDown(() async {
          if (await support.exists()) {
            await support.delete(recursive: true);
          }
        });
        final receiver = AgentHookReceiver(
          statusSink: _FakeStatusSink(),
          applicationSupportDirectory: () async => support,
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(receiver.dispose);
        final settings = AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(codex: true),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            settingsControllerProvider.overrideWithValue(settings),
            agentHookReceiverProvider.overrideWithValue(receiver),
          ],
        );
        addTearDown(container.dispose);

        container.read(agentHookReceiverLifecycleCoordinatorProvider);
        for (var attempt = 0; attempt < 20 && !receiver.isRunning; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(receiver.isRunning, isTrue);
      },
    );

    test('agent hook installer coordinator reconciles runtime hooks', () async {
      final root = await Directory.systemTemp.createTemp(
        'alera-provider-hook-install-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final home = Directory(p.join(root.path, 'home'))
        ..createSync(recursive: true);
      final support = Directory(p.join(root.path, 'support'))
        ..createSync(recursive: true);
      final managedService = ManagedAgentHookInstallService(
        homeDirectory: home.path,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
      );
      final codexRuntimeHome = CodexRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
      );
      final claudeRuntimeHome = ClaudeRuntimeHomeService(
        homeDirectory: home.path,
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': home.path},
        syncMacOSKeychainCredentials: false,
      );
      final settingsController = _TestSettingsController(
        AleraSettings.defaults.copyWith(
          agents: AleraSettings.defaults.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(),
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWith(() => settingsController),
          managedAgentHookInstallServiceProvider.overrideWithValue(
            managedService,
          ),
          codexRuntimeHomeServiceProvider.overrideWithValue(codexRuntimeHome),
          claudeRuntimeHomeServiceProvider.overrideWithValue(claudeRuntimeHome),
        ],
      );
      addTearDown(container.dispose);

      container.read(agentHookInstallerCoordinatorProvider);
      settingsController.setState(
        settingsController.state.copyWith(
          agents: settingsController.state.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(
              codex: true,
              claude: true,
              agy: true,
            ),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        File(p.join(home.path, '.alera', 'agent-hooks', 'alera-agy-hook.sh'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(home.path, '.alera', 'agent-hooks', 'alera-codex-hook.sh'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(home.path, '.alera', 'agent-hooks', 'alera-claude-hook.sh'))
            .existsSync(),
        isTrue,
      );

      settingsController.setState(
        settingsController.state.copyWith(
          agents: settingsController.state.agents.copyWith(
            agentStatusHooks: const AgentStatusHookSettings(),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        (await codexRuntimeHome.status()).state,
        ManagedAgentHookInstallState.notInstalled,
      );
      expect(
        (await claudeRuntimeHome.status()).state,
        ManagedAgentHookInstallState.notInstalled,
      );
    });

    test('agent hook settings map every agent type', () {
      const allEnabled = AgentStatusHookSettings(
        codex: true,
        claude: true,
        copilot: true,
        cursor: true,
        agy: true,
        opencode: true,
        opencode2: true,
        pi: true,
        amp: true,
        grok: true,
        fx: true,
      );
      for (final agentType in AgentType.values) {
        expect(isAgentStatusHookEnabled(allEnabled, agentType), isTrue);
      }
      expect(
        AgentType.values.where(
          (agentType) => isAgentStatusHookEnabled(
            const AgentStatusHookSettings(codex: true, amp: true),
            agentType,
          ),
        ),
        <AgentType>[AgentType.codex, AgentType.amp],
      );
    });

    test(
      'terminal launch environment composes enabled hook runtimes',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'alera-provider-launch-env-',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        final support = Directory(p.join(root.path, 'support'))
          ..createSync(recursive: true);
        final receiver = AgentHookReceiver(
          statusSink: _FakeStatusSink(),
          applicationSupportDirectory: () async => support,
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(receiver.dispose);

        final environment = await terminalLaunchEnvironmentFor(
          agentHookReceiver: receiver,
          codexRuntimeHome: CodexRuntimeHomeService(
            homeDirectory: home.path,
            applicationSupportDirectory: () async => support,
            platform: ManagedAgentHookPlatform.posix,
            environment: <String, String>{'HOME': home.path},
          ),
          claudeRuntimeHome: ClaudeRuntimeHomeService(
            homeDirectory: home.path,
            applicationSupportDirectory: () async => support,
            platform: ManagedAgentHookPlatform.posix,
            environment: <String, String>{'HOME': home.path},
            syncMacOSKeychainCredentials: false,
          ),
          agentRuntimeOverlay: AgentRuntimeOverlayService(
            homeDirectory: home.path,
            platform: ManagedAgentHookPlatform.posix,
            environment: <String, String>{
              'HOME': home.path,
              'SHELL': '/bin/zsh',
            },
            applicationSupportDirectory: () async => support,
          ),
          hooks: const AgentStatusHookSettings(
            codex: true,
            claude: true,
            copilot: true,
            cursor: true,
            opencode: true,
            pi: true,
            amp: true,
          ),
          terminalSessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
        );

        expect(
          environment,
          containsPair('ALERA_TERMINAL_SESSION_ID', 'session-1'),
        );
        expect(environment, contains('CODEX_HOME'));
        expect(environment, contains('CLAUDE_CONFIG_DIR'));
        expect(environment, contains('COPILOT_HOME'));
        // Cursor is intentionally absent: the runtime host builds its
        // per-session plugin, because anything injected here is stripped again
        // by the host's launch-environment sanitisation.
        expect(environment, isNot(contains('ALERA_CURSOR_PLUGIN_DIR')));
        expect(environment, contains('OPENCODE_CONFIG_DIR'));
        expect(environment, contains('PI_CODING_AGENT_DIR'));
        expect(environment, contains('ALERA_AMP_CONFIG_DIR'));
      },
    );

    _registerAppProvidersWrapperPathTests();

    test(
      'terminal launch environment clears overlays for every overlay hook kind',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'alera-provider-launch-env-overlays-',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        final support = Directory(p.join(root.path, 'support'))
          ..createSync(recursive: true);
        final receiver = AgentHookReceiver(
          statusSink: _FakeStatusSink(),
          applicationSupportDirectory: () async => support,
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(receiver.dispose);
        final overlay = AgentRuntimeOverlayService(
          homeDirectory: home.path,
          platform: ManagedAgentHookPlatform.posix,
          environment: <String, String>{'HOME': home.path, 'SHELL': '/bin/zsh'},
          applicationSupportDirectory: () async => support,
        );
        final codex = CodexRuntimeHomeService(
          homeDirectory: home.path,
          applicationSupportDirectory: () async => support,
          platform: ManagedAgentHookPlatform.posix,
          environment: <String, String>{'HOME': home.path},
        );
        final claude = ClaudeRuntimeHomeService(
          homeDirectory: home.path,
          applicationSupportDirectory: () async => support,
          platform: ManagedAgentHookPlatform.posix,
          environment: <String, String>{'HOME': home.path},
          syncMacOSKeychainCredentials: false,
        );

        for (final hooks in const <AgentStatusHookSettings>[
          AgentStatusHookSettings(copilot: true),
          AgentStatusHookSettings(opencode: true),
          AgentStatusHookSettings(pi: true),
          AgentStatusHookSettings(amp: true),
        ]) {
          final environment = await terminalLaunchEnvironmentFor(
            agentHookReceiver: receiver,
            codexRuntimeHome: codex,
            claudeRuntimeHome: claude,
            agentRuntimeOverlay: overlay,
            hooks: hooks,
            terminalSessionId: 'session-${hooks.hashCode}',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
          );

          expect(environment, isNotNull);
        }
      },
    );

    test(
      'terminal launch environment keeps hook metadata on runtime errors',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'alera-provider-launch-error-',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        final support = Directory(p.join(root.path, 'support'))
          ..createSync(recursive: true);
        final receiver = AgentHookReceiver(
          statusSink: _FakeStatusSink(),
          applicationSupportDirectory: () async => support,
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(receiver.dispose);
        Future<Directory> failingSupport() async => throw StateError('boom');

        final environment = await terminalLaunchEnvironmentFor(
          agentHookReceiver: receiver,
          codexRuntimeHome: CodexRuntimeHomeService(
            homeDirectory: home.path,
            applicationSupportDirectory: failingSupport,
            platform: ManagedAgentHookPlatform.posix,
            environment: <String, String>{'HOME': home.path},
          ),
          claudeRuntimeHome: ClaudeRuntimeHomeService(
            homeDirectory: home.path,
            applicationSupportDirectory: failingSupport,
            platform: ManagedAgentHookPlatform.posix,
            environment: <String, String>{'HOME': home.path},
            syncMacOSKeychainCredentials: false,
          ),
          agentRuntimeOverlay: AgentRuntimeOverlayService(
            homeDirectory: home.path,
            platform: ManagedAgentHookPlatform.posix,
            environment: <String, String>{'HOME': home.path},
            applicationSupportDirectory: failingSupport,
          ),
          hooks: const AgentStatusHookSettings(
            codex: true,
            claude: true,
            copilot: true,
            cursor: true,
            opencode: true,
            pi: true,
            amp: true,
          ),
          terminalSessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
        );

        expect(
          environment,
          containsPair('ALERA_TERMINAL_SESSION_ID', 'session-1'),
        );
        expect(environment, isNot(contains('CODEX_HOME')));
        expect(environment, isNot(contains('CLAUDE_CONFIG_DIR')));
        expect(environment, isNot(contains('ALERA_AMP_CONFIG_DIR')));
      },
    );

    test(
      'exit coordinator closes runtime tabs when the workspace is missing',
      () async {
        final runtime = _FakeTerminalRuntime();
        final container = ProviderContainer(
          overrides: [
            terminalRuntimeProvider.overrideWith((ref) => runtime),
            workbenchControllerProvider.overrideWithValue(
              const WorkbenchState(),
            ),
          ],
        );
        addTearDown(() {
          runtime.dispose();
          container.dispose();
        });

        container.read(terminalRuntimeExitCoordinatorProvider);
        runtime.emitExit(
          const TerminalRuntimeExitEvent(
            workspaceId: 'workspace-missing',
            tabId: 'tab-1',
            exitCode: 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(runtime.closedTabIds, <String>['tab-1']);
      },
    );

    test(
      'exit coordinator keeps a failed auto-close setup tab visible',
      () async {
        final runtime = _FakeTerminalRuntime();
        final now = DateTime.utc(2026, 8, 1);
        final workspace = Workspace(
          id: 'workspace-1',
          projectId: 'project-1',
          name: 'Workspace',
          path: '/tmp/workspace',
          createdAt: now,
          updatedAt: now,
          kind: WorkspaceKind.linked,
          status: WorkspaceStatus.active,
        );
        final setupTab = WorkspaceTabRecord(
          id: 'setup-tab',
          workspaceId: workspace.id,
          title: 'Setup',
          createdAt: now,
          updatedAt: now,
          payload: const <String, Object?>{
            workspaceTabAutoCloseOnSuccessPayloadKey: true,
          },
        );
        final container = ProviderContainer(
          overrides: [
            terminalRuntimeProvider.overrideWith((ref) => runtime),
            workbenchControllerProvider.overrideWithValue(
              WorkbenchState(
                workspacesByProject: <String, List<Workspace>>{
                  workspace.projectId: <Workspace>[workspace],
                },
                tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
                  workspace.id: <WorkspaceTabRecord>[setupTab],
                },
              ),
            ),
          ],
        );
        addTearDown(() {
          runtime.dispose();
          container.dispose();
        });

        container.read(terminalRuntimeExitCoordinatorProvider);
        runtime.emitExit(
          const TerminalRuntimeExitEvent(
            workspaceId: 'workspace-1',
            tabId: 'setup-tab',
            exitCode: 1,
            autoCloseOnSuccess: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(runtime.closedTabIds, isEmpty);
      },
    );

    test('exit coordinator leaves command terminal sessions alone', () async {
      final runtime = _FakeTerminalRuntime();
      final container = ProviderContainer(
        overrides: [
          terminalRuntimeProvider.overrideWith((ref) => runtime),
          workbenchControllerProvider.overrideWithValue(const WorkbenchState()),
        ],
      );
      addTearDown(() {
        runtime.dispose();
        container.dispose();
      });

      container.read(terminalRuntimeExitCoordinatorProvider);
      runtime.emitExit(
        const TerminalRuntimeExitEvent(
          workspaceId: commandTerminalWorkspaceId,
          tabId: 'command-tab',
          exitCode: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // The dialog owns that session, and closing it here would wipe the output
      // the moment the shell exited.
      expect(runtime.closedTabIds, isEmpty);
    });

    test('database and launcher providers create disposable concrete implementations', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-app-providers-',
      );
      addTearDown(() async {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } on PathNotFoundException {
          // Some provider disposal paths can race the test cleanup after the
          // fake app-support directory has already been removed.
        }
      });
      final previousPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      addTearDown(() => PathProviderPlatform.instance = previousPlatform);

      final container = ProviderContainer();
      final db = await container.read(aleraDatabaseProvider.future);

      expect(
        container.read(externalUriLauncherProvider),
        isA<UrlLauncherExternalUriLauncher>(),
      );
      expect(container.read(projectRepositoryProvider), isNotNull);
      expect(container.read(workbenchRepositoryProvider), isNotNull);
      expect(container.read(settingsRepositoryProvider), isNotNull);
      expect(container.read(projectsServiceProvider), isNotNull);
      expect(await db.customSelect('SELECT 1 AS value').getSingle(), isNotNull);

      await db.close();
      container.dispose();
    });
  });
}
