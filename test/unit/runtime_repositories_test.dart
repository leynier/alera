import 'dart:async';

import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/projects/infra/runtime_project_repository.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/runtime_settings_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_managed_workspace_client.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_graph_repository.dart';
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
        isPinned: true,
      ),
    ];
    final workspaces = await repository.listWorkspaces('project-1');
    expect(workspaces.single.hostId, 'remote-mac');
    expect(workspaces.single.tagIds, <String>['review', 'mobile']);
    expect(workspaces.single.tagNames, <String>['Review', 'Mobile']);
    expect(workspaces.single.parentWorkspaceId, 'parent-1');
    expect(workspaces.single.childCount, 2);
    expect(workspaces.single.isPinned, isTrue);
  });
  test('RuntimeWorkspaceGraphRepository maps tag and relation RPCs', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeWorkspaceGraphRepository(client);
    client.responses['workspaceTag.list'] = <Object?>[
      _workspaceTagJson(id: 'tag-1', name: 'Review'),
    ];
    client.responses['workspaceTag.upsert'] = _workspaceTagJson(
      id: 'tag-2',
      name: 'Mobile',
    );
    client.responses['workspaceRelation.list'] = <Object?>[
      _workspaceRelationJson(id: 'relation-1'),
    ];
    client.responses['workspaceRelation.link'] = _workspaceRelationJson(
      id: 'relation-2',
      parentWorkspaceId: 'parent-2',
      childWorkspaceId: 'child-2',
    );
    final tags = await repository.listTags();
    final created = await repository.upsertTag(
      WorkspaceTag.create(name: 'Mobile', now: DateTime.utc(2026, 6, 27)),
    );
    await repository.assignTag(workspaceId: 'workspace-1', tagId: 'tag-1');
    await repository.unassignTag(workspaceId: 'workspace-1', tagId: 'tag-1');
    final relations = await repository.listRelations();
    final relation = await repository.linkWorkspaces(
      parentWorkspaceId: 'parent-2',
      childWorkspaceId: 'child-2',
    );
    await repository.unlinkWorkspaces(
      parentWorkspaceId: 'parent-2',
      childWorkspaceId: 'child-2',
    );
    expect(tags.single.name, 'Review');
    expect(created.color, WorkspaceTag.defaultColor);
    expect(relations.single.parentWorkspaceId, 'parent-1');
    expect(relation.childWorkspaceId, 'child-2');
    expect(client.requests, <String>[
      'workspaceTag.list',
      'workspaceTag.upsert',
      'workspaceTag.assign',
      'workspaceTag.unassign',
      'workspaceRelation.list',
      'workspaceRelation.link',
      'workspaceRelation.unlink',
    ]);
    expect(client.payloads['workspaceTag.assign']!.single, <String, Object?>{
      'workspaceId': 'workspace-1',
      'tagId': 'tag-1',
    });
  });
  test(
    'RuntimeSettingsRepository waits for migration before runtime reads',
    () async {
      final client = _FakeRuntimeHostClient();
      final legacy = _MemorySettingsRepository()
        ..settings = AleraSettings.defaults.copyWith(
          general: const GeneralSettings(workspaceDirectory: '/legacy'),
        );
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacy,
        beforeAccess: () async {
          client.responses['runtimeSettings.get'] = <String, Object?>{
            'workspaceDirectory': '/migrated',
          };
        },
      );

      final settings = await repository.load();

      expect(settings.general.workspaceDirectory, '/migrated');
      expect(client.requests, <String>['runtimeSettings.get']);
    },
  );

  test(
    'RuntimeManagedWorkspaceClient uses long-running RPC timeouts',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeManagedWorkspaceClient(client);
      client.responses['workspace.createManaged'] = <String, Object?>{
        'workspace': _workspaceJson(id: 'workspace-1'),
        'setupReport': <String, Object?>{'steps': <Object?>[]},
      };

      await repository.createLinkedWorkspace(
        project: _project(id: 'project-1', name: 'Alera'),
        sourceBranch: 'main',
        newBranchName: 'feature/managed',
        reuseExistingBranch: false,
      );
      await repository.removeWorkspace(
        workspace: _workspace(id: 'workspace-1', projectId: 'project-1'),
        deleteBranch: true,
      );

      expect(client.timeouts['workspace.createManaged'], <Duration?>[
        const Duration(minutes: 30),
      ]);
      expect(client.timeouts['workspace.removeManaged'], <Duration?>[
        const Duration(minutes: 10),
      ]);
    },
  );

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
          projectConfigRepository: _MemoryProjectConfigRepository(),
          settingsRepository: _MemorySettingsRepository(),
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
    expect(client.requests, hasLength(10));
    expect(
      client.requests.where((request) => request == 'runtimeSettings.update'),
      hasLength(2),
    );
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
  bool isPinned = false,
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
    'isPinned': isPinned,
    'tagIds': tagIds,
    'tagNames': tagNames,
    'parentWorkspaceId': parentWorkspaceId,
    'childCount': childCount,
  };
}

Map<String, Object?> _workspaceTagJson({
  required String id,
  required String name,
  String color = WorkspaceTag.defaultColor,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'color': color,
    'createdAt': '2026-06-27T00:00:00.000Z',
    'updatedAt': '2026-06-27T00:00:00.000Z',
  };
}

Map<String, Object?> _workspaceRelationJson({
  required String id,
  String parentWorkspaceId = 'parent-1',
  String childWorkspaceId = 'child-1',
}) {
  return <String, Object?>{
    'id': id,
    'parentWorkspaceId': parentWorkspaceId,
    'parentInstanceId': 'instance-$parentWorkspaceId',
    'childWorkspaceId': childWorkspaceId,
    'childInstanceId': 'instance-$childWorkspaceId',
    'createdAt': '2026-06-27T00:00:00.000Z',
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
  final timeouts = <String, List<Duration?>>{};
  final _events = StreamController<RuntimeHostEvent>.broadcast();
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(type);
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    timeouts.putIfAbsent(type, () => <Duration?>[]).add(timeout);
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

final class _MemoryProjectConfigRepository implements ProjectConfigRepository {
  final configs = <String, ProjectConfig>{};
  @override
  Future<ProjectConfig?> findByProjectId(String projectId) async {
    return configs[projectId];
  }

  @override
  Future<Map<String, ProjectConfig>> loadAll() async {
    return Map<String, ProjectConfig>.of(configs);
  }

  @override
  Stream<Map<String, ProjectConfig>> watchAll() {
    return Stream<Map<String, ProjectConfig>>.value(configs);
  }

  @override
  Future<void> save({
    required String projectId,
    required ProjectConfig config,
    required DateTime updatedAt,
  }) async {
    configs[projectId] = config;
  }

  @override
  Future<void> remove(String projectId) async {
    configs.remove(projectId);
  }
}

final class _MemorySettingsRepository implements SettingsRepository {
  AleraSettings settings = AleraSettings.defaults;

  @override
  Future<AleraSettings> load() async => settings;

  @override
  Future<void> save(AleraSettings settings) async {
    this.settings = settings;
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
  Future<Workspace> setWorkspacePinned(
    String workspaceId,
    bool isPinned,
  ) async {
    final workspace = workspaces[workspaceId]!;
    return upsertWorkspace(workspace.copyWith(isPinned: isPinned));
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
