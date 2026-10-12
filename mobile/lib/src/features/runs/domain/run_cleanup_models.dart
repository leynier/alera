import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';

/// A worktree and branch an isolated run kept, as `runs.resources` lists it.
class const RunResource({
  required final String workspaceId,
  required final String name,
  final String? branch,
  final String path = '',
  final String? taskId,
  final int attempt = 0,
  final String phase = '',
  final bool registered = true,
  final String? cleanupId,
  final String? cleanupState,
  final bool retired = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    final identity = json.mapValue('identity');
    final workspace = identity.mapValue('workspace');
    final id = workspace.requiredString('id');
    return RunResource(
      workspaceId: id,
      name: workspace.optionalString('name') ?? id,
      branch: workspace.optionalString('branch'),
      path: workspace.optionalString('path') ?? '',
      taskId: identity.optionalString('taskId'),
      attempt: runInt(identity['attempt']),
      phase: json.optionalString('phase') ?? '',
      registered: json['registered'] != false,
      cleanupId: json.optionalString('cleanupId'),
      cleanupState: json.optionalString('cleanupState'),
      retired: json['retired'] == true,
    );
  }

  /// Retired resources and those held by a cleanup in progress cannot be
  /// selected again.
  bool get selectable =>
      !retired &&
      (cleanupState == null ||
          cleanupState == 'preview' ||
          cleanupState == 'abandoned');
}

class const RunResourcePage({
  required final List<RunResource> items,
  final int? nextBeforeRow,
}) {
  factory fromJson(Map<String, Object?> json) => RunResourcePage(
    items: <RunResource>[
      for (final item in json.objectList('items'))
        RunResource.fromJson(asJsonMap(item)),
    ],
    nextBeforeRow: runOptionalInt(json['nextBeforeRow']),
  );
}

/// One earlier cleanup of the run (`runs.cleanups`).
class const RunCleanupHistoryEntry({
  required final String id,
  required final String state,
  final String? error,
  final int resourceCount = 0,
  final int retiredCount = 0,
}) {
  factory fromJson(Map<String, Object?> json) => RunCleanupHistoryEntry(
    id: json.requiredString('id'),
    state: json.optionalString('state') ?? '',
    error: json.optionalString('error'),
    resourceCount: runInt(json['resourceCount']),
    retiredCount: runInt(json['retiredCount']),
  );
}

/// What the user chose to remove: a workspace and whether its branch goes.
class const RunCleanupSelection({
  required final String workspaceId,
  final bool removeBranch = false,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'removeBranch': removeBranch,
  };
}

/// One resource of a preview, with the Git state that was inspected.
class const RunCleanupItem({
  required final String workspaceId,
  required final String name,
  final String? branch,
  final bool removeBranch = false,
  final String headSha = '',
  final bool dirty = false,
  final bool operationInProgress = false,
  final bool locked = false,
  final List<String> changedPaths = const <String>[],
  final bool pathsTruncated = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    final workspace = json.mapValue('identity').mapValue('workspace');
    final git = json.mapValue('git');
    final id = workspace.requiredString('id');
    return RunCleanupItem(
      workspaceId: id,
      name: workspace.optionalString('name') ?? id,
      branch: workspace.optionalString('branch'),
      removeBranch: json['removeBranch'] == true,
      headSha: git.optionalString('headSha') ?? '',
      dirty: git['dirty'] == true,
      operationInProgress: git['operationInProgress'] == true,
      locked: git['locked'] == true,
      changedPaths: git.stringList('changedPaths'),
      pathsTruncated: git['pathsTruncated'] == true,
    );
  }

  /// Uncommitted work, a Git operation or a lock that removal would discard
  /// or break.
  bool get hasRisk => dirty || operationInProgress || locked;
}

/// A reviewed cleanup. Applying it needs this exact [id] and [digest].
class const RunCleanupPreview({
  required final String id,
  required final String runId,
  required final String digest,
  final int expiresAt = 0,
  final List<RunCleanupItem> items = const <RunCleanupItem>[],
}) {
  factory fromJson(Map<String, Object?> json) => RunCleanupPreview(
    id: json.requiredString('id'),
    runId: json.optionalString('runId') ?? '',
    digest: json.requiredString('digest'),
    expiresAt: runInt(json['expiresAt']),
    items: <RunCleanupItem>[
      for (final item in json.objectList('items'))
        RunCleanupItem.fromJson(asJsonMap(item)),
    ],
  );
}

enum RunCleanupState {
  preview,
  applying,
  retired,
  attention,
  abandoned,
  unknown;

  static RunCleanupState parse(String? value) => values.firstWhere(
    (state) => state.name == value && state != unknown,
    orElse: () => unknown,
  );
}

/// `runs.cleanup`: where an applied preview stands.
class const RunCleanupStatus({
  required final RunCleanupPreview preview,
  required final RunCleanupState state,
  final String? error,
  final List<String> retiredWorkspaceIds = const <String>[],
}) {
  factory fromJson(Map<String, Object?> json) => RunCleanupStatus(
    preview: RunCleanupPreview.fromJson(json.mapValue('preview')),
    state: RunCleanupState.parse(json.optionalString('state')),
    error: json.optionalString('error'),
    retiredWorkspaceIds: json.stringList('retiredWorkspaceIds'),
  );

  static RunCleanupStatus? tryParse(Map<String, Object?> json) {
    if (asJsonMap(json['preview']).optionalString('id') == null) return null;
    return RunCleanupStatus.fromJson(json);
  }
}
