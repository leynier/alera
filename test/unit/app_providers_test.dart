import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

Project _project({required String id, required String path}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Project(
    id: id,
    name: 'Alera',
    repoPath: path,
    createdAt: now,
    updatedAt: now,
    kind: ProjectKind.gitRepository,
  );
}

String _slugSegment(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_/]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

class _TestSettingsController extends SettingsController {
  _TestSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;

  void setState(AleraSettings next) {
    state = next;
  }
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final List<Workspace> workspaces = <Workspace>[];
  final List<WorkspaceTabRecord> tabs = <WorkspaceTabRecord>[];
  final Map<String, WorkbenchLayout> layouts = <String, WorkbenchLayout>{};

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    for (final workspace in workspaces) {
      if (workspace.id == workspaceId) {
        return workspace;
      }
    }
    return null;
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    return layouts[workspaceId];
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    return tabs
        .where((tab) => tab.workspaceId == workspaceId)
        .toList(growable: false);
  }

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    return workspaces
        .where((workspace) => workspace.projectId == projectId)
        .toList(growable: false);
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    tabs.removeWhere((tab) => tab.id == tabId);
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    tabs.removeWhere((tab) => tab.workspaceId == workspaceId);
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    workspaces.removeWhere((workspace) => workspace.id == workspaceId);
    if (cascadeTabs) {
      await removeWorkspaceTabsForWorkspace(workspaceId);
    }
    await removeWorkbenchLayout(workspaceId);
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    final removed = workspaces
        .where((workspace) => workspace.projectId == projectId)
        .toList(growable: false);
    workspaces.removeWhere((workspace) => workspace.projectId == projectId);
    for (final workspace in removed) {
      await removeWorkbenchLayout(workspace.id);
    }
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    layouts.remove(workspaceId);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    final index = tabs.indexWhere((entry) => entry.id == tab.id);
    if (index == -1) {
      tabs.add(tab);
    } else {
      tabs[index] = tab;
    }
    return tab;
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    layouts[layout.workspaceId] = layout;
    return layout;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    final index = workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index == -1) {
      workspaces.add(workspace);
    } else {
      workspaces[index] = workspace;
    }
    return workspace;
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    return const Stream<List<WorkspaceTabRecord>>.empty();
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    return const Stream<List<Workspace>>.empty();
  }
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  List<String> sourceBranches = <String>['main'];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      _ProcessCall(
        executable: executable,
        arguments: List<String>.from(arguments),
        workingDirectory: workingDirectory,
      ),
    );

    if (arguments.contains('for-each-ref')) {
      return ProcessRunOutput(
        exitCode: 0,
        stdout: '${sourceBranches.join('\n')}\n',
        stderr: '',
      );
    }
    if (arguments.length >= 2 &&
        arguments[0] == 'check-ref-format' &&
        arguments[1] == '--branch') {
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }
    if (arguments.length >= 4 &&
        arguments[0] == 'rev-parse' &&
        arguments[1] == '--verify' &&
        arguments[2] == '--quiet') {
      return const ProcessRunOutput(exitCode: 1, stdout: '', stderr: '');
    }
    if (arguments.length >= 5 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'add') {
      Directory(arguments[4]).createSync(recursive: true);
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

class _ProcessCall {
  const _ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  @override
  Future<void> open(Uri uri) async {}
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final StreamController<TerminalRuntimeExitEvent> _events =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _events.stream;

  void emitExit(TerminalRuntimeExitEvent event) {
    _events.add(event);
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
  }

  @override
  void closeWorkspace(String workspaceId) {}

  @override
  void dispose() {
    _events.close();
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    throw UnimplementedError();
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}
