import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_monitor_providers.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 21);

void main() {
  test('a project that lives only on a host is monitored through its remote '
      'workspace', () {
    final local = _project('local', '/repo/local');
    final remoteOnly = _project(
      'remote',
      '/srv/only-there',
    ).copyWith(primaryHostId: 'ssh-box');
    final container = _container(
      WorkbenchState(
        bootstrapped: true,
        projects: <Project>[local, remoteOnly],
        workspacesByProject: <String, List<Workspace>>{
          local.id: <Workspace>[_workspace('local-task', local.id)],
          remoteOnly.id: <Workspace>[
            _workspace('remote-task', remoteOnly.id, hostId: 'ssh-box'),
            _workspace(
              'remote-main',
              remoteOnly.id,
              hostId: 'ssh-box',
              path: '/srv/only-there',
            ),
          ],
        },
      ),
    );
    addTearDown(container.dispose);

    final configuration = container.read(
      workspacePullRequestMonitorConfigurationProvider,
    );

    final byWorkspace = <String, String>{
      for (final target in configuration.targets)
        target.workspaceId: target.repoPath,
    };
    expect(byWorkspace, <String, String>{
      'local-task': '/repo/local',
      // The path is inside a remote workspace, so the git backend and the
      // forge CLI route it to the host instead of reading `repoPath` here.
      'remote-task': '/srv/only-there',
      'remote-main': '/srv/only-there',
    });
  });

  test('a remote-only project without a workspace on its folder uses any '
      'remote workspace, and none without one', () {
    final worktreesOnly = _project(
      'worktrees',
      '/srv/worktrees',
    ).copyWith(primaryHostId: 'ssh-box');
    final unopened = _project(
      'unopened',
      '/srv/unopened',
    ).copyWith(primaryHostId: 'ssh-box');
    final container = _container(
      WorkbenchState(
        bootstrapped: true,
        projects: <Project>[worktreesOnly, unopened],
        workspacesByProject: <String, List<Workspace>>{
          worktreesOnly.id: <Workspace>[
            _workspace('feature-a', worktreesOnly.id, hostId: 'ssh-box'),
            _workspace('feature-b', worktreesOnly.id, hostId: 'ssh-box'),
          ],
          unopened.id: <Workspace>[
            // A local workspace record on a remote-only project is not a
            // route to the host, so it cannot stand in for the folder.
            _workspace('stray-local', unopened.id),
          ],
        },
      ),
    );
    addTearDown(container.dispose);

    final configuration = container.read(
      workspacePullRequestMonitorConfigurationProvider,
    );

    expect(configuration.targets.map((target) => target.workspaceId), <String>[
      'feature-a',
      'feature-b',
    ]);
    expect(
      configuration.targets.map((target) => target.repoPath).toSet(),
      <String>{'/workspaces/feature-a'},
    );
  });
}

ProviderContainer _container(WorkbenchState state) {
  return ProviderContainer(
    overrides: [
      settingsControllerProvider.overrideWith(_Settings.new),
      workbenchControllerProvider.overrideWith(() => _Workbench(state)),
      effectiveHostingProviderOverrideProvider.overrideWith(
        (ref, projectId) async => null,
      ),
    ],
  );
}

class _Settings extends SettingsController {
  @override
  AleraSettings build() => .defaults;
}

class _Workbench(final WorkbenchState _seed) extends WorkbenchController {
  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}
}

Project _project(String id, String repoPath) {
  return Project(
    id: id,
    name: id,
    repoPath: repoPath,
    createdAt: _now,
    updatedAt: _now,
  );
}

Workspace _workspace(
  String id,
  String projectId, {
  String hostId = 'local',
  String? path,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: id,
    path: path ?? '/workspaces/$id',
    branch: 'feature/$id',
    hostId: hostId,
    createdAt: _now,
    updatedAt: _now,
    kind: .linked,
    status: .active,
  );
}
