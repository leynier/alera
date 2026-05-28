import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_awake_assertions.dart';
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
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

part 'app_providers_test_harness.dart';

void main() {
  group('app providers', () {
    test(
      'workspaceServiceProvider uses the configured workspace root override',
      () async {
        final processRunner = _FakeProcessRunner();
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
            processRunnerProvider.overrideWithValue(processRunner),
            projectServiceProvider.overrideWithValue(
              ProjectService(processRunner),
            ),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(workspaceServiceProvider);
        final workspace = await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/coverage',
        );

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
          processRunner.calls.any(
            (call) =>
                call.workingDirectory == repoPath &&
                call.arguments.length >= 5 &&
                call.arguments[0] == 'worktree' &&
                call.arguments[1] == 'add' &&
                call.arguments[4] == workspace.path,
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
      'terminalHostWarmupProvider starts the host with settings config',
      () async {
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

        container.read(terminalHostWarmupProvider);
        await Future<void>.delayed(Duration.zero);

        expect(client.ensureStartedConfigs, hasLength(1));
        expect(
          client.ensureStartedConfigs.single.toJson(),
          const TerminalHostConfig(
            emptyShutdownDelaySeconds: 7,
            detachedSessionShutdownDelaySeconds: 14,
            scrollbackBytes: 4096,
          ).toJson(),
        );
      },
    );

    test(
      'notification coordinator emits native notifications for done states',
      () async {
        final presenter = _FakeNotificationPresenter();
        final settings = AleraSettings.defaults.copyWith(
          general: AleraSettings.defaults.general.copyWith(
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

    test('agent awake coordinator follows working agent statuses', () async {
      final displayLock = _FakeAwakeDisplayLock();
      final assertion = _FakeAwakeAssertion();
      final settings = AleraSettings.defaults.copyWith(
        general: AleraSettings.defaults.general.copyWith(
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

    test('agent awake assertions include Windows system sleep lock', () {
      final container = ProviderContainer(
        overrides: [
          processRunnerProvider.overrideWithValue(_FakeProcessRunner()),
        ],
      );
      addTearDown(container.dispose);

      final assertions = container.read(agentAwakeAssertionsProvider);

      expect(assertions, contains(isA<MacosSystemSleepAssertion>()));
      expect(assertions, contains(isA<LinuxLidSleepAssertion>()));
      expect(assertions, contains(isA<WindowsSystemSleepAssertion>()));
    });

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
      'database and launcher providers create disposable concrete implementations',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'alera-app-providers-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
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
        expect(
          await db.customSelect('SELECT 1 AS value').getSingle(),
          isNotNull,
        );

        container.dispose();
        await Future<void>.delayed(Duration.zero);
      },
    );
  });
}
