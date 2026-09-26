enum RunBoardBucket { attention, active, history }

class RunBoardCursor {
  const RunBoardCursor(this.createdAt, this.id, this.revision);

  factory RunBoardCursor.fromJson(Map<String, Object?> json) => RunBoardCursor(
    json['created_at'] as String,
    json['id'] as String,
    json['revision'] as int,
  );

  final String createdAt;
  final String id;
  final int revision;

  Map<String, Object?> toJson() => {
    'created_at': createdAt,
    'id': id,
    'revision': revision,
  };
}

class RunBoardQuery {
  const RunBoardQuery({
    this.projectId,
    this.workspaceId,
    this.search,
    this.bucket,
    this.cursor,
    this.limit = 50,
  });

  final String? projectId;
  final String? workspaceId;
  final String? search;
  final RunBoardBucket? bucket;
  final RunBoardCursor? cursor;
  final int limit;

  Map<String, Object?> toJson() => {
    if (projectId != null) 'project_id': projectId,
    if (workspaceId != null) 'workspace_id': workspaceId,
    if (search != null) 'search': search,
    if (bucket != null) 'bucket': bucket!.name,
    if (cursor != null) 'cursor': cursor!.toJson(),
    'limit': limit,
  };
}

class RunBoardCounts {
  const RunBoardCounts({
    required this.attention,
    required this.active,
    required this.history,
  });

  factory RunBoardCounts.fromJson(Map<String, Object?> json) => RunBoardCounts(
    attention: json['attention'] as int,
    active: json['active'] as int,
    history: json['history'] as int,
  );

  final int attention;
  final int active;
  final int history;
}

class RunSummary {
  const RunSummary({
    required this.id,
    required this.objective,
    required this.status,
    required this.bucket,
    required this.workspaceId,
    required this.createdAt,
    required this.lastActivityAt,
    required this.policyStatus,
    required this.taskCount,
    required this.completedCount,
    required this.runningCount,
    required this.failedCount,
    required this.stalledCount,
    required this.blockedCount,
    required this.pendingGateCount,
    this.workspaceName,
    this.projectId,
    this.projectName,
  });

  factory RunSummary.fromJson(Map<String, Object?> json) => RunSummary(
    id: json['id'] as String,
    objective: json['objective'] as String,
    status: json['status'] as String,
    bucket: RunBoardBucket.values.byName(json['bucket'] as String),
    workspaceId: json['workspace_id'] as String,
    workspaceName: json['workspace_name'] as String?,
    projectId: json['project_id'] as String?,
    projectName: json['project_name'] as String?,
    createdAt: json['created_at'] as String,
    lastActivityAt: json['last_activity_at'] as String,
    policyStatus: json['policy_status'] as String,
    taskCount: json['task_count'] as int,
    completedCount: json['completed_count'] as int,
    runningCount: json['running_count'] as int,
    failedCount: json['failed_count'] as int,
    stalledCount: json['stalled_count'] as int,
    blockedCount: json['blocked_count'] as int,
    pendingGateCount: json['pending_gate_count'] as int,
  );

  final String id;
  final String objective;
  final String status;
  final RunBoardBucket bucket;
  final String workspaceId;
  final String? workspaceName;
  final String? projectId;
  final String? projectName;
  final String createdAt;
  final String lastActivityAt;
  final String policyStatus;
  final int taskCount;
  final int completedCount;
  final int runningCount;
  final int failedCount;
  final int stalledCount;
  final int blockedCount;
  final int pendingGateCount;
}

class RunBoardSnapshot {
  RunBoardSnapshot({
    required this.revision,
    required this.counts,
    required List<RunSummary> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);

  factory RunBoardSnapshot.fromJson(Map<String, Object?> json) =>
      RunBoardSnapshot(
        revision: json['revision'] as int,
        counts: RunBoardCounts.fromJson(boardJsonObject(json['counts'])),
        items: [
          for (final item in json['items'] as List)
            RunSummary.fromJson(boardJsonObject(item)),
        ],
        nextCursor: json['next_cursor'] == null
            ? null
            : RunBoardCursor.fromJson(boardJsonObject(json['next_cursor'])),
      );

  final int revision;
  final RunBoardCounts counts;
  final List<RunSummary> items;
  final RunBoardCursor? nextCursor;
}

Map<String, Object?> boardJsonObject(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Run board payload must be an object.');
  }
  return Map<String, Object?>.from(payload);
}
