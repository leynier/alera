import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/projects/infra/runtime_project_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'RuntimeProjectRepository refreshes project stream from runtime events',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeProjectRepository(client);
      client.responseSequences['project.list'] = <Object?>[
        <Object?>[_projectJson(id: 'project-1', name: 'Alera')],
        <Object?>[
          _projectJson(id: 'project-1', name: 'Alera'),
          _projectJson(id: 'project-2', name: 'Mobile'),
        ],
      ];

      final expectation = expectLater(
        repository.watchAll(),
        emitsInOrder(<Matcher>[
          predicate<List<Project>>(
            (projects) =>
                projects.map((project) => project.name).join(',') == 'Alera',
          ),
          predicate<List<Project>>(
            (projects) =>
                projects.map((project) => project.name).join(',') ==
                'Alera,Mobile',
          ),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      client.emit(
        const RuntimeHostEvent('projectsChanged', <String, Object?>{}),
      );

      await expectation;
    },
  );

  test('RuntimeWorkbenchRepository parses workspace graph metadata', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeWorkbenchRepository(client);
    client.responses['workspace.list'] = <Object?>[
      _workspaceJson(
        id: 'workspace-1',
        tagIds: <String>['review', 'mobile'],
        tagNames: <String>['Review', 'Mobile'],
        parentWorkspaceId: 'parent-1',
        childCount: 2,
      ),
    ];

    final workspaces = await repository.listWorkspaces('project-1');

    expect(workspaces.single.hostId, 'remote-mac');
    expect(workspaces.single.tagIds, <String>['review', 'mobile']);
    expect(workspaces.single.tagNames, <String>['Review', 'Mobile']);
    expect(workspaces.single.parentWorkspaceId, 'parent-1');
    expect(workspaces.single.childCount, 2);
  });

  test(
    'RuntimeSshTargetRepository parses targets and bootstrap progress',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeSshTargetRepository(client);
      client.responses['sshTarget.list'] = <Object?>[
        _sshTargetJson(id: 'remote-1', bootstrapStatus: 'installed'),
      ];

      final targets = await repository.list();
      final progressFuture = repository.watchBootstrapProgress().first;
      await Future<void>.delayed(Duration.zero);
      client.emit(
        const RuntimeHostEvent('sshTargetBootstrapProgress', <String, Object?>{
          'jobId': 'job-1',
          'targetId': 'remote-1',
          'status': 'installing',
          'stage': 'upload',
          'message': 'Uploading Runtime Artifact',
        }),
      );
      final progress = await progressFuture;

      expect(targets.single.bootstrapStatus, SshBootstrapStatus.installed);
      expect(targets.single.installDir, '/home/alera/.alera/runtime');
      expect(progress.targetId, 'remote-1');
      expect(progress.status, SshBootstrapStatus.installing);
      expect(client.requests, <String>['sshTarget.list']);
    },
  );

  test('RuntimeSshTargetRepository passes runtime archive defaults', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeSshTargetRepository(
      client,
      bootstrapDefaults: const RuntimeSshBootstrapDefaults(
        channel: 'rc',
        archiveUrl:
            'https://github.com/leynier/alera/releases/download/v1.2.4-rc.0/runtime-archive-rc.json',
        version: '1.2.4-rc.0',
      ),
    );
    client.responses['sshTarget.bootstrap.start'] = <String, Object?>{
      'jobId': 'job-1',
      'targetId': 'remote-1',
      'status': 'installing',
    };

    final job = await repository.startBootstrap(
      targetId: 'remote-1',
      installDir: '/opt/alera/runtime',
      platform: 'linux',
      arch: 'arm64',
    );

    expect(job.jobId, 'job-1');
    expect(client.payloads['sshTarget.bootstrap.start']?.single, <
      String,
      Object?
    >{
      'targetId': 'remote-1',
      'installDir': '/opt/alera/runtime',
      'platform': 'linux',
      'arch': 'arm64',
      'channel': 'rc',
      'archiveUrl':
          'https://github.com/leynier/alera/releases/download/v1.2.4-rc.0/runtime-archive-rc.json',
      'version': '1.2.4-rc.0',
    });
  });

  test('RuntimeStateMigration seeds legacy state once', () async {
    final client = _FakeRuntimeHostClient();
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
    expect(client.requests, <String>[
      'runtimeMetadata.get',
      'runtimeMetadata.set',
    ]);
  });
}

Map<String, Object?> _projectJson({required String id, required String name}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'repoPath': '/tmp/$id',
    'createdAt': '2026-06-27T00:00:00.000Z',
    'updatedAt': '2026-06-27T00:00:00.000Z',
    'kind': ProjectKind.gitRepository.name,
  };
}

final _timestamp = DateTime.utc(2026, 6, 27);

Project _project({required String id, required String name}) {
  return Project(
    id: id,
    name: name,
    repoPath: '/tmp/$id',
    createdAt: _timestamp,
    updatedAt: _timestamp,
    kind: ProjectKind.gitRepository,
  );
}

Workspace _workspace({required String id, required String projectId}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: 'Workspace',
    path: '/tmp/$id',
    createdAt: _timestamp,
    updatedAt: _timestamp,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
  );
}

Map<String, Object?> _workspaceJson({
  required String id,
  List<String> tagIds = const <String>[],
  List<String> tagNames = const <String>[],
  String? parentWorkspaceId,
  int childCount = 0,
}) {
  return <String, Object?>{
    'id': id,
    'instanceId': 'instance-$id',
    'hostId': 'remote-mac',
    'projectId': 'project-1',
    'name': 'Feature',
    'branch': 'feature/mobile',
    'path': '/tmp/workspace',
    'createdAt': '2026-06-27T00:00:00.000Z',
    'updatedAt': '2026-06-27T00:00:00.000Z',
    'kind': WorkspaceKind.linked.name,
    'status': WorkspaceStatus.active.name,
    'sourceBranch': 'main',
    'reusesExistingBranch': false,
    'tagIds': tagIds,
    'tagNames': tagNames,
    'parentWorkspaceId': parentWorkspaceId,
    'childCount': childCount,
  };
}

Map<String, Object?> _sshTargetJson({
  required String id,
  required String bootstrapStatus,
}) {
  return <String, Object?>{
    'id': id,
    'alias': 'Build Host',
    'host': 'build.example.test',
    'port': 22,
    'username': 'alera',
    'platform': 'linux',
    'arch': 'x64',
    'authKind': 'agent',
    'createdAt': '2026-06-27T00:00:00.000Z',
    'updatedAt': '2026-06-27T00:00:00.000Z',
    'lastStatus': null,
    'installDir': '/home/alera/.alera/runtime',
    'runtimeVersion': '1.2.3',
    'runtimePlatform': 'linux',
    'runtimeArch': 'x64',
    'bootstrapStatus': bootstrapStatus,
    'lastBootstrapAt': '2026-06-27T00:01:00.000Z',
    'lastCheckedAt': '2026-06-27T00:02:00.000Z',
    'lastError': null,
  };
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final responseSequences = <String, List<Object?>>{};
  final requests = <String>[];
  final payloads = <String, List<Map<String, Object?>>>{};
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    requests.add(type);
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    final sequence = responseSequences[type];
    if (sequence != null && sequence.isNotEmpty) {
      return sequence.removeAt(0);
    }
    return responses[type];
  }

  void emit(RuntimeHostEvent event) {
    _events.add(event);
  }
}

final class _MemoryProjectRepository implements ProjectRepository {
  final projects = <Project>[];

  @override
  Future<List<Project>> listAll() async => List<Project>.of(projects);

  @override
  Stream<List<Project>> watchAll() => Stream<List<Project>>.value(projects);

  @override
  Future<Project> add(Project project) async {
    projects.removeWhere((candidate) => candidate.id == project.id);
    projects.add(project);
    return project;
  }

  @override
  Future<Project> update(Project project) => add(project);

  @override
  Future<void> remove(String projectId) async {
    projects.removeWhere((project) => project.id == projectId);
  }
}

final class _MemoryWorkbenchRepository implements WorkbenchRepository {
  final workspaces = <String, Workspace>{};
  final tabs = <String, WorkspaceTabRecord>{};
  final layouts = <String, WorkbenchLayout>{};

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    return <Workspace>[
      for (final workspace in workspaces.values)
        if (workspace.projectId == projectId && workspace.isActive) workspace,
    ];
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    return Stream<List<Workspace>>.value(
      workspaces.values
          .where(
            (workspace) =>
                workspace.projectId == projectId && workspace.isActive,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    return workspaces[workspaceId];
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    workspaces[workspace.id] = workspace;
    return workspace;
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    workspaces.remove(workspaceId);
    if (cascadeTabs) {
      tabs.removeWhere((_, tab) => tab.workspaceId == workspaceId);
    }
    layouts.remove(workspaceId);
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    final ids = workspaces.values
        .where((workspace) => workspace.projectId == projectId)
        .map((workspace) => workspace.id)
        .toList(growable: false);
    for (final id in ids) {
      await removeWorkspace(id);
    }
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    return <WorkspaceTabRecord>[
      for (final tab in tabs.values)
        if (tab.workspaceId == workspaceId) tab,
    ];
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    return Stream<List<WorkspaceTabRecord>>.value(
      tabs.values
          .where((tab) => tab.workspaceId == workspaceId)
          .toList(growable: false),
    );
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    return tabs[tabId];
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    tabs[tab.id] = tab;
    return tab;
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    tabs.remove(tabId);
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    tabs.removeWhere((_, tab) => tab.workspaceId == workspaceId);
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    return layouts[workspaceId];
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    layouts[layout.workspaceId] = layout;
    return layout;
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    layouts.remove(workspaceId);
  }
}
