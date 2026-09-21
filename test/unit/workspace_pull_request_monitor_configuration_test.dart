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
  test('a project that lives only on a host is not monitored', () {
    final local = _project('local', '/repo/local');
    final remoteOnly = _project(
      'remote',
      '/srv/only-there',
    ).copyWith(primaryHostId: 'ssh-box');
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_Settings.new),
        workbenchControllerProvider.overrideWith(
          () => _Workbench(
            WorkbenchState(
              bootstrapped: true,
              projects: <Project>[local, remoteOnly],
              workspacesByProject: <String, List<Workspace>>{
                local.id: <Workspace>[_workspace('local-task', local.id)],
                remoteOnly.id: <Workspace>[
                  _workspace('remote-task', remoteOnly.id, hostId: 'ssh-box'),
                ],
              },
            ),
          ),
        ),
        effectiveHostingProviderOverrideProvider.overrideWith(
          (ref, projectId) async => null,
        ),
      ],
    );
    addTearDown(container.dispose);

    final configuration = container.read(
      workspacePullRequestMonitorConfigurationProvider,
    );

    expect(configuration.targets.map((target) => target.workspaceId), <String>[
      'local-task',
    ]);
    expect(configuration.targets.single.repoPath, '/repo/local');
  });
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

Workspace _workspace(String id, String projectId, {String hostId = 'local'}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: id,
    path: '/workspaces/$id',
    branch: 'feature/$id',
    hostId: hostId,
    createdAt: _now,
    updatedAt: _now,
    kind: .linked,
    status: .active,
  );
}
