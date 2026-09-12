enum WorkflowCleanupState { preview, applying, attention, retired }

class WorkflowCleanupIdentity {
  WorkflowCleanupIdentity.fromJson(Map json)
    : runId = json['runId']! as String,
      taskId = json['taskId'] as String?,
      attempt = json['attempt']! as int,
      baseSha = json['baseSha']! as String,
      id = (json['workspace']! as Map)['id']! as String,
      name = (json['workspace']! as Map)['name']! as String,
      path = (json['workspace']! as Map)['path']! as String,
      branch = (json['workspace']! as Map)['branch']! as String;

  final String runId;
  final String? taskId;
  final int attempt;
  final String baseSha;
  final String id;
  final String name;
  final String path;
  final String branch;
}

class WorkflowCleanupResource {
  WorkflowCleanupResource.fromJson(Map json)
    : identity = WorkflowCleanupIdentity.fromJson(json['identity']! as Map),
      phase = json['phase']! as String,
      registered = json['registered']! as bool,
      retired = json['retired']! as bool,
      cleanupId = json['cleanupId'] as String?,
      cleanupState = json['cleanupState'] == null
          ? null
          : WorkflowCleanupState.values.byName(json['cleanupState']! as String);

  final WorkflowCleanupIdentity identity;
  final String phase;
  final bool registered;
  final bool retired;
  final String? cleanupId;
  final WorkflowCleanupState? cleanupState;
  bool get canSelect =>
      registered &&
      !retired &&
      cleanupId == null &&
      (phase == 'ready' || phase == 'attention');
}

class WorkflowCleanupSummary {
  WorkflowCleanupSummary.fromJson(Map json)
    : id = json['id']! as String,
      state = WorkflowCleanupState.values.byName(json['state']! as String),
      error = json['error'] as String?,
      resourceCount = json['resourceCount']! as int,
      retiredCount = json['retiredCount']! as int {
    if (resourceCount < 1 ||
        resourceCount > 25 ||
        retiredCount < 0 ||
        retiredCount > resourceCount) {
      throw const FormatException('Invalid cleanup resource counts.');
    }
  }
  final String id;
  final WorkflowCleanupState state;
  final String? error;
  final int resourceCount;
  final int retiredCount;
}

class WorkflowCleanupPage<T> {
  WorkflowCleanupPage.fromJson(
    Map<String, Object?> json,
    T Function(Map) decode,
  ) : runId = json['runId']! as String,
      revision = json['revision']! as int,
      nextBeforeRow = json['nextBeforeRow'] as int?,
      items = List.unmodifiable(
        (json['items']! as List).map((item) => decode(item as Map)),
      ) {
    if (revision < 0 || items.length > 25) {
      throw const FormatException('Invalid cleanup page.');
    }
  }
  final String runId;
  final int revision;
  final int? nextBeforeRow;
  final List<T> items;
  void requireRun(String expected) {
    if (runId != expected) {
      throw const FormatException('Cleanup belongs to another run.');
    }
  }
}

class WorkflowCleanupItem {
  WorkflowCleanupItem.fromJson(Map json)
    : identity = WorkflowCleanupIdentity.fromJson(json['identity']! as Map),
      removeBranch = json['removeBranch']! as bool,
      headSha = (json['git']! as Map)['headSha']! as String,
      dirty = (json['git']! as Map)['dirty']! as bool,
      locked = (json['git']! as Map)['locked']! as bool,
      operationInProgress =
          (json['git']! as Map)['operationInProgress']! as bool,
      pathsTruncated = (json['git']! as Map)['pathsTruncated']! as bool,
      changedPaths = List.unmodifiable(
        ((json['git']! as Map)['changedPaths']! as List).cast<String>(),
      ) {
    if (changedPaths.length > 128) {
      throw const FormatException('Oversized cleanup path preview.');
    }
  }
  final WorkflowCleanupIdentity identity;
  final bool removeBranch;
  final String headSha;
  final bool dirty;
  final bool locked;
  final bool operationInProgress;
  final bool pathsTruncated;
  final List<String> changedPaths;
  bool get blocked => dirty || locked || operationInProgress;
}

class WorkflowCleanupPreview {
  WorkflowCleanupPreview.fromJson(Map<String, Object?> json)
    : id = json['id']! as String,
      runId = json['runId']! as String,
      digest = json['digest']! as String,
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAt']! as int) * 1000,
        isUtc: true,
      ),
      items = List.unmodifiable(
        (json['items']! as List).map(
          (item) => WorkflowCleanupItem.fromJson(item as Map),
        ),
      ) {
    if (items.isEmpty ||
        items.length > 25 ||
        items.map((item) => item.identity.id).toSet().length != items.length ||
        items.any((item) => item.identity.runId != runId)) {
      throw const FormatException('Invalid cleanup selection.');
    }
  }
  final String id;
  final String runId;
  final String digest;
  final DateTime expiresAt;
  final List<WorkflowCleanupItem> items;
  bool canConfirm(DateTime now) =>
      now.isBefore(expiresAt) && !items.any((item) => item.blocked);
  void requireIdentity(String expectedId, String expectedRun) {
    if (id != expectedId || runId != expectedRun) {
      throw const FormatException(
        'Cleanup preview does not match the selection.',
      );
    }
  }
}

class WorkflowCleanupStatus {
  WorkflowCleanupStatus.fromJson(Map<String, Object?> json)
    : preview = WorkflowCleanupPreview.fromJson(
        Map<String, Object?>.from(json['preview']! as Map),
      ),
      state = WorkflowCleanupState.values.byName(json['state']! as String),
      error = json['error'] as String?,
      retiredWorkspaceIds = Set.unmodifiable(
        (json['retiredWorkspaceIds']! as List).cast<String>(),
      ) {
    final ids = preview.items.map((item) => item.identity.id).toSet();
    if (retiredWorkspaceIds.length !=
            (json['retiredWorkspaceIds']! as List).length ||
        !ids.containsAll(retiredWorkspaceIds) ||
        (state == WorkflowCleanupState.retired &&
            retiredWorkspaceIds.length != ids.length) ||
        (state == WorkflowCleanupState.preview &&
            retiredWorkspaceIds.isNotEmpty)) {
      throw const FormatException(
        'Cleanup receipt does not match its resources.',
      );
    }
  }
  WorkflowCleanupStatus.forPreview(this.preview)
    : state = WorkflowCleanupState.preview,
      error = null,
      retiredWorkspaceIds = const {};
  final WorkflowCleanupPreview preview;
  final WorkflowCleanupState state;
  final String? error;
  final Set<String> retiredWorkspaceIds;
}
