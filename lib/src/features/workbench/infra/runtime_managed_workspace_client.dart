import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_removal_dependencies.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_hand_on_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_storage_impact.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/workspace_buffer_guard_request.dart';
import 'package:uuid/uuid.dart';

const Duration _managedWorkspaceCreateTimeout = Duration(minutes: 30);
const Duration _managedWorkspaceRemoveTimeout = Duration(minutes: 10);

class RuntimeManagedWorkspaceClient(
  final RuntimeHostClient _client, {
  final Future<void> Function()? beforeAccess,
}) implements
    ManagedWorkspaceRuntime,
    SharedWorkspaceRuntime,
    WorkspaceRemovalDependencyRuntime,
    ProjectRemovalDependencyRuntime,
    WorkspaceStorageRuntime {
  @override
  Future<List<WorkspaceRemovalDependency>> removalDependencies(
    String workspaceId,
  ) => _removalDependencies(workspaceId, 'workspace');

  @override
  Future<List<WorkspaceRemovalDependency>> projectRemovalDependencies(
    String projectId,
  ) => _removalDependencies(projectId, 'project');

  Future<List<WorkspaceRemovalDependency>> _removalDependencies(
    String id,
    String owner,
  ) async {
    await _ensureReady();
    final result = await _client.runtimeRequest(
      '$owner.removalDependencies',
      <String, Object?>{'id': id},
    );
    if (result is! List) {
      throw StateError('Could not verify automation dependencies.');
    }
    return result
        .map((item) => WorkspaceRemovalDependency.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  @override
  Future<void> pauseRemovalDependencies(
    String workspaceId,
    List<WorkspaceRemovalDependency> approved,
  ) => _pauseRemovalDependencies(workspaceId, approved, 'workspace');

  @override
  Future<void> pauseProjectRemovalDependencies(
    String projectId,
    List<WorkspaceRemovalDependency> approved,
  ) => _pauseRemovalDependencies(projectId, approved, 'project');

  Future<void> _pauseRemovalDependencies(
    String id,
    List<WorkspaceRemovalDependency> approved,
    String owner,
  ) async {
    await _ensureReady();
    final approvedIds = approved.map((dependency) => dependency.id).toSet();
    for (final dependency in approved.where(
      (dependency) => dependency.requiresPause,
    )) {
      await _client.runtimeRequest('automation.pause', <String, Object?>{
        'id': dependency.id,
        'activeRuns': 'cancel-active',
        'reason': '$owner removal requested',
      });
    }
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final pending = (await _removalDependencies(
        id,
        owner,
      )).where((dependency) => dependency.requiresPause).toList();
      if (pending.isEmpty) return;
      if (pending.any((dependency) => !approvedIds.contains(dependency.id))) {
        throw StateError(
          'Automation dependencies changed. Refresh and confirm their impact again.',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Automation shutdown has not completed. The $owner was preserved; retry when its runs have stopped.',
        );
      }
      await Future.pause(const Duration(milliseconds: 250));
    }
  }

  @override
  Future<WorkspaceCreationResult> createSharedWorkspace({
    required Project project,
    String? name,
    String? hostId,
    String? issueUrl,
  }) async {
    await _ensureReady();
    if (issueUrl?.trim().isNotEmpty == true) {
      await _ensureLinkedIssuesCapability();
    }
    final payload = await _client.runtimeRequest(
      'workspace.createShared',
      <String, Object?>{
        'projectId': project.id,
        'name': ?name,
        'hostId': ?hostId,
        if (issueUrl?.trim().isNotEmpty == true) 'issueUrl': issueUrl!.trim(),
      },
      _managedWorkspaceCreateTimeout,
    );
    return workspaceCreationResultFromRuntime(_asMap(payload));
  }

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
    String? hostId,
    String? issueUrl,
  }) async {
    await _ensureReady();
    final remoteHostId = normalizedRemoteHostId(hostId);
    if (remoteHostId != null) {
      await _ensureRemoteWorkspaceCapability();
    }
    final linkedIssueUrl = issueUrl?.trim();
    final linksIssue = linkedIssueUrl != null && linkedIssueUrl.isNotEmpty;
    if (linksIssue) {
      await _ensureLinkedIssuesCapability();
    }
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
    if (remoteHostId != null) {
      request['hostId'] = remoteHostId;
    }
    if (linksIssue) {
      request['issueUrl'] = linkedIssueUrl;
    }
    try {
      final payload = await _client.runtimeRequest(
        'workspace.createManaged',
        request,
        _managedWorkspaceCreateTimeout,
      );
      return workspaceCreationResultFromRuntime(_asMap(payload));
    } catch (error) {
      throw WorkspaceException(userFacingExceptionMessage(error));
    }
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
    if (workspace.isMain) {
      await requestWithWorkspaceBufferGuard(
        request: _client.runtimeRequest,
        workspaceId: workspace.id,
        operation: 'removeShared',
        payload: request,
        timeout: _managedWorkspaceRemoveTimeout,
      );
    } else {
      await _client.runtimeRequest(
        'workspace.removeManaged',
        request,
        _managedWorkspaceRemoveTimeout,
      );
    }
  }

  @override
  Future<WorkspaceCreationResult> handOffWorkspace({
    String? relocationId,
    required Workspace workspace,
    required String branch,
    required bool reuseExistingBranch,
    bool moveChanges = true,
    String? replacementBranch,
    String? name,
  }) async {
    await _ensureReady();
    await _ensureSafeHandoff();
    final request = <String, Object?>{
      'relocationId': relocationId ?? const Uuid().v4(),
      'id': workspace.id,
      'branch': branch,
      'reuseExistingBranch': reuseExistingBranch,
      'deferSetup': true,
      'moveChanges': moveChanges,
      'replacementBranch': replacementBranch,
      'sharedImpactConfirmed': true,
    };
    if (name != null) {
      request['name'] = name;
    }
    final payload = await requestWithWorkspaceBufferGuard(
      request: _client.runtimeRequest,
      workspaceId: workspace.id,
      operation: 'handOff',
      payload: request,
      timeout: _managedWorkspaceCreateTimeout,
    );
    return workspaceCreationResultFromRuntime(_asMap(payload));
  }

  @override
  Future<WorkspaceHandOnResult> handOnWorkspace({
    String? relocationId,
    required Workspace workspace,
    String? activeWorkspaceId,
  }) async {
    await _ensureReady();
    await _ensureSafeHandoff();
    final request = <String, Object?>{
      'relocationId': relocationId ?? const Uuid().v4(),
      'id': workspace.id,
      'closeSessions': true,
      'sharedImpactConfirmed': true,
    };
    if (activeWorkspaceId != null) {
      request['activeWorkspaceId'] = activeWorkspaceId;
    }
    final json = _asMap(
      await requestWithWorkspaceBufferGuard(
        request: _client.runtimeRequest,
        workspaceId: workspace.id,
        operation: 'handOn',
        payload: request,
        timeout: _managedWorkspaceRemoveTimeout,
      ),
    );
    return WorkspaceHandOnResult(
      workspace: _workspaceFromJson(_asMap(json['workspace'])),
      removedWorkspaceId: json['removedWorkspaceId'] as String?,
    );
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }

  Future<void> _ensureSafeHandoff() async {
    final status = _asMap(await _client.runtimeRequest('status.get'));
    final capabilities = status['runtimeCapabilities'];
    if (capabilities is! List ||
        !capabilities.contains(aleraRuntimeHostSafeHandoffCapability)) {
      throw WorkspaceException(
        'The running runtime does not support safe workspace transfers. Update and restart the runtime before Hand Off or Hand On.',
      );
    }
  }

  Future<void> _ensureLinkedIssuesCapability() async {
    final status = _asMap(await _client.runtimeRequest('status.get'));
    final capabilities = status['runtimeCapabilities'];
    if (capabilities is! List ||
        !capabilities.contains(aleraRuntimeHostLinkedIssuesCapability)) {
      throw WorkspaceException(
        'The running runtime cannot link issues. Update and restart the runtime, or create the workspace without an issue.',
      );
    }
  }

  Future<void> _ensureRemoteWorkspaceCapability() async {
    final status = _asMap(await _client.runtimeRequest('status.get'));
    final capabilities = status['runtimeCapabilities'];
    if (capabilities is! List ||
        !capabilities.contains(aleraRuntimeHostRemoteSshWorkspacesCapability)) {
      throw WorkspaceException(remoteHostMissingCapabilityMessage());
    }
  }
}

WorkspaceCreationResult workspaceCreationResultFromRuntime(
  Map<String, Object?> json,
) {
  return WorkspaceCreationResult(
    workspace: _workspaceFromJson(_asMap(json['workspace'])),
    setupReport: _setupReportFromJson(_asMap(json['setupReport'])),
    deferredSetupCommand: _emptyToNull(json['deferredSetupCommand']),
  );
}

WorktreeSetupReport _setupReportFromJson(Map<String, Object?> json) {
  final steps = _asList(json['steps'])
      .map(_setupStepReportFromJson)
      .toList(growable: false);
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
