import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/application/workspace_section_repository.dart';

import 'dart:async';

import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

part 'runtime_workbench_sections.dart';

class RuntimeWorkbenchRepository(
  @override final RuntimeHostClient _client, {
  final Future<void> Function()? beforeAccess,
  RuntimeChangeCoalescer? coalescer,
}) with _RuntimeWorkbenchSections implements WorkbenchRepository {
  this : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  @override
  final RuntimeChangeCoalescer _coalescer;

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspace.list',
      <String, Object?>{'projectId': projectId},
      runtimeSnapshotRequestTimeout,
    );
    return _asList(payload).map(_workspaceFromJson).toList(growable: false);
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{
        'workspacesChanged',
        'workspaceTagsChanged',
        'workspaceRelationsChanged',
      },
      readSnapshot: () => listWorkspaces(projectId),
      coalesceKey: 'workspaces:$projectId',
      coalescer: _coalescer,
      matchesScope: runtimeScopeMatcher('projectId', projectId),
    );
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
  Future<Workspace> setWorkspacePinned(
    String workspaceId,
    bool isPinned,
  ) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspace.setPinned',
      <String, Object?>{'id': workspaceId, 'isPinned': isPinned},
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
    }, runtimeSnapshotRequestTimeout);
    return _asList(payload)
        .map(_tabFromJson)
        .whereType<WorkspaceTabRecord>()
        .toList(growable: false);
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'workspaceTabsChanged'},
      readSnapshot: () => listWorkspaceTabs(workspaceId),
      coalesceKey: 'tabs:$workspaceId',
      coalescer: _coalescer,
      matchesScope: runtimeScopeMatcher('workspaceId', workspaceId),
    );
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
  Future<WorkspaceTabRecord> upsertWorkspaceTab(
    WorkspaceTabRecord tab, {
    bool manualRename = false,
  }) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      manualRename ? 'tab.rename' : 'tab.upsert',
      manualRename
          ? <String, Object?>{'id': tab.id, 'title': tab.title}
          : _tabToJson(tab),
    );
    return _tabFromJson(_asMap(payload)) ??
        (throw StateError('Workspace tab upsert returned a retired tab kind.'));
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    await _ensureReady();
    try {
      await _removeWorkspaceTab(tabId);
    } on TerminalHostRequestTimeoutException catch (error) {
      if (error.requestType != 'tab.remove') {
        rethrow;
      }
      // The host may commit after the client stops waiting. Replaying this
      // idempotent removal obtains an authoritative response instead of
      // treating an ambiguous timeout as success.
      await _removeWorkspaceTab(tabId);
    } on TerminalHostConnectionClosedException {
      // The request may have reached the host before the disconnect. The
      // sidecar's remove contract is idempotent, so one replay is safe.
      await _removeWorkspaceTab(tabId);
    }
  }

  Future<void> _removeWorkspaceTab(String tabId) async {
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

  @override
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
    isPinned: json['isPinned'] == true,
    tagIds: _stringList(json['tagIds']),
    tagNames: _stringList(json['tagNames']),
    sectionId: _emptyToNull(json['sectionId']),
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
    'isPinned': workspace.isPinned,
    'tagIds': workspace.tagIds,
    'tagNames': workspace.tagNames,
    'parentWorkspaceId': workspace.parentWorkspaceId,
    'childCount': workspace.childCount,
  };
}

WorkspaceTabRecord? _tabFromJson(Map<String, Object?> json) {
  final kind = WorkspaceTabKind.tryParse(json['kind']);
  if (kind == null) {
    return null;
  }
  return WorkspaceTabRecord(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    kind: kind,
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
