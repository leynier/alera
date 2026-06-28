import 'dart:async';

import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeWorkbenchRepository implements WorkbenchRepository {
  RuntimeWorkbenchRepository(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspace.list',
      <String, Object?>{'projectId': projectId},
    );
    return _asList(payload).map(_workspaceFromJson).toList(growable: false);
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) async* {
    yield await listWorkspaces(projectId);
    await for (final event in _client.runtimeEvents) {
      if (event.name == 'workspacesChanged' ||
          event.name == 'workspaceTagsChanged' ||
          event.name == 'workspaceRelationsChanged') {
        yield await listWorkspaces(projectId);
      }
    }
  }

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspace.find',
      <String, Object?>{'id': workspaceId},
    );
    if (payload == null) {
      return null;
    }
    return _workspaceFromJson(_asMap(payload));
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspace.upsert',
      _workspaceToJson(workspace),
    );
    return _workspaceFromJson(_asMap(payload));
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    await _ensureReady();
    await _client.runtimeRequest('workspace.remove', <String, Object?>{
      'id': workspaceId,
      'cascadeTabs': cascadeTabs,
    });
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    await _ensureReady();
    await _client.runtimeRequest(
      'workspace.removeForProject',
      <String, Object?>{'projectId': projectId},
    );
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest('tab.list', <String, Object?>{
      'workspaceId': workspaceId,
    });
    return _asList(payload).map(_tabFromJson).toList(growable: false);
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(
    String workspaceId,
  ) async* {
    yield await listWorkspaceTabs(workspaceId);
    await for (final event in _client.runtimeEvents) {
      if (event.name == 'workspaceTabsChanged') {
        yield await listWorkspaceTabs(workspaceId);
      }
    }
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest('tab.find', <String, Object?>{
      'id': tabId,
    });
    if (payload == null) {
      return null;
    }
    return _tabFromJson(_asMap(payload));
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest('tab.upsert', _tabToJson(tab));
    return _tabFromJson(_asMap(payload));
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    await _ensureReady();
    await _client.runtimeRequest('tab.remove', <String, Object?>{'id': tabId});
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    await _ensureReady();
    await _client.runtimeRequest('tab.removeForWorkspace', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'layout.find',
      <String, Object?>{'workspaceId': workspaceId},
    );
    if (payload == null) {
      return null;
    }
    final map = _asMap(payload);
    return WorkbenchLayout.fromJson(_asMap(map['data']));
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'layout.upsert',
      <String, Object?>{
        'workspaceId': layout.workspaceId,
        'data': layout.toMap(),
      },
    );
    final map = _asMap(payload);
    return WorkbenchLayout.fromJson(_asMap(map['data']));
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    await _ensureReady();
    await _client.runtimeRequest('layout.remove', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }
}

Workspace _workspaceFromJson(Map<String, Object?> json) {
  return Workspace(
    id: json['id'] as String,
    instanceId: json['instanceId'] as String?,
    hostId: (json['hostId'] as String?) ?? 'local',
    projectId: json['projectId'] as String,
    name: json['name'] as String,
    branch: _emptyToNull(json['branch']),
    path: json['path'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    kind: WorkspaceKind.values.firstWhere(
      (kind) => kind.name == json['kind'],
      orElse: () => WorkspaceKind.linked,
    ),
    status: WorkspaceStatus.values.firstWhere(
      (status) => status.name == json['status'],
      orElse: () => WorkspaceStatus.active,
    ),
    sourceBranch: _emptyToNull(json['sourceBranch']),
    reusesExistingBranch: json['reusesExistingBranch'] == true,
    tagIds: _stringList(json['tagIds']),
    tagNames: _stringList(json['tagNames']),
    parentWorkspaceId: _emptyToNull(json['parentWorkspaceId']),
    childCount: (json['childCount'] as num?)?.toInt() ?? 0,
  );
}

Map<String, Object?> _workspaceToJson(Workspace workspace) {
  return <String, Object?>{
    'id': workspace.id,
    'instanceId': workspace.instanceId ?? '',
    'hostId': workspace.hostId,
    'projectId': workspace.projectId,
    'name': workspace.name,
    'branch': workspace.branch,
    'path': workspace.path,
    'createdAt': workspace.createdAt.toUtc().toIso8601String(),
    'updatedAt': workspace.updatedAt.toUtc().toIso8601String(),
    'kind': workspace.kind.name,
    'status': workspace.status.name,
    'sourceBranch': workspace.sourceBranch,
    'reusesExistingBranch': workspace.reusesExistingBranch,
    'tagIds': workspace.tagIds,
    'tagNames': workspace.tagNames,
    'parentWorkspaceId': workspace.parentWorkspaceId,
    'childCount': workspace.childCount,
  };
}

WorkspaceTabRecord _tabFromJson(Map<String, Object?> json) {
  return WorkspaceTabRecord(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    kind: WorkspaceTabKind.fromJson(json['kind']),
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    payload: _asMap(json['payload']),
  );
}

Map<String, Object?> _tabToJson(WorkspaceTabRecord tab) {
  return <String, Object?>{
    'id': tab.id,
    'workspaceId': tab.workspaceId,
    'kind': tab.kind.key,
    'title': tab.title,
    'createdAt': tab.createdAt.toUtc().toIso8601String(),
    'updatedAt': tab.updatedAt.toUtc().toIso8601String(),
    'payload': tab.payload,
  };
}

List<Map<String, Object?>> _asList(Object? value) {
  if (value is List) {
    return <Map<String, Object?>>[for (final item in value) _asMap(item)];
  }
  return const <Map<String, Object?>>[];
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException(
    'Runtime workbench payload must be a JSON object.',
  );
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return <String>[
    for (final item in value)
      if (item is String) item,
  ];
}

String? _emptyToNull(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}
