import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_storage_impact.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const Duration _managedWorkspaceCreateTimeout = Duration(minutes: 30);
const Duration _managedWorkspaceRemoveTimeout = Duration(minutes: 10);

class RuntimeManagedWorkspaceClient
    implements ManagedWorkspaceRuntime, WorkspaceStorageRuntime {
  RuntimeManagedWorkspaceClient(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

  @override
  Future<WorkspaceStorageImpact> storageImpact({
    required String workspaceId,
    String? activeWorkspaceId,
  }) async {
    await _ensureReady();
    final request = <String, Object?>{'id': workspaceId, 'closeSessions': true};
    if (activeWorkspaceId != null) {
      request['activeWorkspaceId'] = activeWorkspaceId;
    }
    final json = _asMap(
      await _client.runtimeRequest(
        'workspace.storageImpact',
        request,
        _managedWorkspaceRemoveTimeout,
      ),
    );
    return WorkspaceStorageImpact(
      workspaceId: json['workspaceId'] as String,
      path: json['path'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      entryCount: (json['entryCount'] as num).toInt(),
      measuredAt: DateTime.parse(json['measuredAt'] as String).toUtc(),
      lastActivityAt: DateTime.parse(json['lastActivityAt'] as String).toUtc(),
      safeToClean: json['safeToClean'] == true,
      blockers: _stringList(json['blockers']),
    );
  }

  @override
  Future<WorkspaceCreationResult> createLinkedWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    String? name,
  }) async {
    await _ensureReady();
    final request = <String, Object?>{
      'projectId': project.id,
      'branch': newBranchName,
      'reuseExistingBranch': reuseExistingBranch,
      // The desktop shows the worktree setup in a "Setup" terminal instead of
      // holding the create dialog open until it finishes. A host that predates
      // the flag ignores it and runs the setup inline, as before.
      'deferSetup': true,
    };
    if (!reuseExistingBranch) {
      request['sourceBranch'] = sourceBranch;
    }
    if (name != null) {
      request['name'] = name;
    }
    final payload = await _client.runtimeRequest(
      'workspace.createManaged',
      request,
      _managedWorkspaceCreateTimeout,
    );
    return _creationResultFromJson(_asMap(payload));
  }

  @override
  Future<void> removeWorkspace({
    required Workspace workspace,
    bool? deleteBranch,
    String? activeWorkspaceId,
  }) async {
    await _ensureReady();
    final request = <String, Object?>{
      'id': workspace.id,
      'closeSessions': true,
    };
    if (activeWorkspaceId != null) {
      request['activeWorkspaceId'] = activeWorkspaceId;
    }
    if (deleteBranch != null) {
      request['deleteBranch'] = deleteBranch;
    }
    await _client.runtimeRequest(
      'workspace.removeManaged',
      request,
      _managedWorkspaceRemoveTimeout,
    );
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }
}

WorkspaceCreationResult _creationResultFromJson(Map<String, Object?> json) {
  return WorkspaceCreationResult(
    workspace: _workspaceFromJson(_asMap(json['workspace'])),
    setupReport: _setupReportFromJson(_asMap(json['setupReport'])),
    deferredSetupCommand: _emptyToNull(json['deferredSetupCommand']),
  );
}

WorktreeSetupReport _setupReportFromJson(Map<String, Object?> json) {
  final steps = _asList(
    json['steps'],
  ).map(_setupStepReportFromJson).toList(growable: false);
  return WorktreeSetupReport(steps: steps);
}

WorktreeSetupStepReport _setupStepReportFromJson(Map<String, Object?> json) {
  return WorktreeSetupStepReport(
    kind: WorktreeSetupStepKind.values.firstWhere(
      (kind) => kind.name == json['kind'],
      orElse: () => WorktreeSetupStepKind.config,
    ),
    label: json['label'] as String,
    succeeded: json['succeeded'] == true,
    message: _emptyToNull(json['message']),
    exitCode: (json['exitCode'] as num?)?.toInt(),
    stdoutTail: _emptyToNull(json['stdoutTail']),
    stderrTail: _emptyToNull(json['stderrTail']),
  );
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
    'Runtime managed workspace payload must be a JSON object.',
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
