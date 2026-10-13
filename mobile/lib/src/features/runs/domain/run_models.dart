import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// The runtime writes UTC timestamps either as RFC 3339 or as SQLite's
/// `YYYY-MM-DD HH:MM:SS`.
DateTime? parseRunTimestamp(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final trimmed = value.trim();
  final iso = trimmed.contains('T')
      ? trimmed
      : '${trimmed.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(iso)?.toUtc();
}

int runInt(Object? value) => value is int ? value : 0;

int? runOptionalInt(Object? value) => value is int ? value : null;

/// Board groups, as the runtime derives them.
enum RunBucket {
  attention('Attention'),
  active('Active'),
  history('History');

  RunBucket(this.label);

  final String label;

  static RunBucket parse(String? value) => values.firstWhere(
    (bucket) => bucket.name == value,
    orElse: () => RunBucket.active,
  );
}

enum RunIsolation {
  isolated('Isolated'),
  shared('Shared');

  RunIsolation(this.label);

  final String label;

  static RunIsolation parse(String? value) =>
      value == 'shared' ? shared : isolated;
}

/// Opaque board page position; sent back exactly as received.
class const RunBoardCursor({
  required final String createdAt,
  required final String id,
  required final int revision,
}) {
  static RunBoardCursor? tryParse(Object? value) {
    final json = asJsonMap(value);
    final createdAt = json.optionalString('createdAt');
    final id = json.optionalString('id');
    if (createdAt == null || id == null) return null;
    return RunBoardCursor(
      createdAt: createdAt,
      id: id,
      revision: runInt(json['revision']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'createdAt': createdAt,
    'id': id,
    'revision': revision,
  };
}

/// One run as the board lists it.
class const RunSummary({
  required final String id,
  required final String objective,
  required final String status,
  required final RunBucket bucket,
  required final String workspaceId,
  final String? workspaceName,
  final String? projectId,
  final String? projectName,
  final DateTime? createdAt,
  final DateTime? lastActivityAt,
  final DateTime? completedAt,
  final bool planGatePending = false,
  final RunIsolation isolation = RunIsolation.isolated,
  final bool approvalRequired = false,
  final int? planRevision,
  final String? attentionReason,
  final String coordinatorState = 'none',
  final String? pausedBy,
  final int controlSequence = 0,
  final List<String> pendingGateKinds = const <String>[],
  final int taskCount = 0,
  final int completedCount = 0,
  final int runningCount = 0,
  final int failedCount = 0,
  final int stalledCount = 0,
  final int blockedCount = 0,
  final int pendingGateCount = 0,
  final bool cleanupAttention = false,
  final bool cleanupApplying = false,
  final List<RunPendingGateRef> pendingGates = const <RunPendingGateRef>[],
}) {
  factory fromJson(Map<String, Object?> json) => RunSummary(
    id: json.requiredString('id'),
    objective: json.optionalString('objective') ?? '',
    status: json.optionalString('status') ?? 'planning',
    bucket: RunBucket.parse(json.optionalString('bucket')),
    workspaceId: json.optionalString('workspaceId') ?? '',
    workspaceName: json.optionalString('workspaceName'),
    projectId: json.optionalString('projectId'),
    projectName: json.optionalString('projectName'),
    createdAt: parseRunTimestamp(json.optionalString('createdAt')),
    lastActivityAt: parseRunTimestamp(json.optionalString('lastActivityAt')),
    completedAt: parseRunTimestamp(json.optionalString('completedAt')),
    planGatePending: json['planGatePending'] == true,
    isolation: RunIsolation.parse(json.optionalString('isolation')),
    approvalRequired: json['approvalRequired'] == true,
    planRevision: runOptionalInt(json['planRevision']),
    attentionReason: json.optionalString('attentionReason'),
    coordinatorState: json.optionalString('coordinatorState') ?? 'none',
    pausedBy: json.optionalString('pausedBy'),
    controlSequence: runInt(json['controlSequence']),
    pendingGateKinds: json.stringList('pendingGateKinds'),
    taskCount: runInt(json['taskCount']),
    completedCount: runInt(json['completedCount']),
    runningCount: runInt(json['runningCount']),
    failedCount: runInt(json['failedCount']),
    stalledCount: runInt(json['stalledCount']),
    blockedCount: runInt(json['blockedCount']),
    pendingGateCount: runInt(json['pendingGateCount']),
    cleanupAttention: json['cleanupAttention'] == true,
    cleanupApplying: json['cleanupApplying'] == true,
    pendingGates: <RunPendingGateRef>[
      for (final item in json.objectList('pendingGates'))
        ?RunPendingGateRef.tryParse(item),
    ],
  );

  /// Completed, failed or cancelled with nothing left to settle.
  bool get isFinished =>
      status == 'completed' ||
      status == 'failed' ||
      (status == 'cancelled' && completedAt != null);

  /// A cancel that is still stopping workers and terminals.
  bool get isCancelling => status == 'cancelled' && completedAt == null;

  String get workspaceLabel =>
      <String>[?projectName, workspaceName ?? workspaceId].join(' / ');
}

/// A due gate a board row names, newest first (at most five), so a tap can
/// open it without reading the run's gates. Older hosts send none.
class const RunPendingGateRef({
  required final String id,
  required final RunGateKind kind,
  final String? taskId,
}) {
  static RunPendingGateRef? tryParse(Object? value) {
    final json = asJsonMap(value);
    final id = json.optionalString('id');
    if (id == null) return null;
    return RunPendingGateRef(
      id: id,
      kind: RunGateKind.parse(json.optionalString('kind')),
      taskId: json.optionalString('taskId'),
    );
  }
}

class const RunBoardCounts({
  final int attention = 0,
  final int active = 0,
  final int history = 0,
}) {
  factory fromJson(Map<String, Object?> json) => RunBoardCounts(
    attention: runInt(json['attention']),
    active: runInt(json['active']),
    history: runInt(json['history']),
  );

  int countFor(RunBucket bucket) => switch (bucket) {
    RunBucket.attention => attention,
    RunBucket.active => active,
    RunBucket.history => history,
  };
}

class const RunBoardPage({
  required final int revision,
  required final RunBoardCounts counts,
  required final List<RunSummary> items,
  final RunBoardCursor? nextCursor,
}) {
  factory fromJson(Map<String, Object?> json) => RunBoardPage(
    revision: runInt(json['revision']),
    counts: RunBoardCounts.fromJson(json.mapValue('counts')),
    items: <RunSummary>[
      for (final item in json.objectList('items'))
        RunSummary.fromJson(asJsonMap(item)),
    ],
    nextCursor: RunBoardCursor.tryParse(json['nextCursor']),
  );
}

enum RunGateKind {
  decision,
  stall,
  plan,
  stage,
  unknown;

  static RunGateKind parse(String? value) => values.firstWhere(
    (kind) => kind.name == value && kind != unknown,
    orElse: () => unknown,
  );
}

enum RunGateStatus {
  pending,
  resolved,
  timeout,
  invalidated,
  unknown;

  static RunGateStatus parse(String? value) => values.firstWhere(
    (status) => status.name == value && status != unknown,
    orElse: () => unknown,
  );
}

/// Exact option ids the runtime accepts for plan and stage gates.
const List<String> runReviewGateOptions = <String>[
  'approve',
  'requestChanges',
  'reject',
];

/// Exact option ids the runtime accepts for stall gates.
const List<String> runStallGateOptions = <String>[
  'killAndFailover',
  'keepWaiting',
  'abortStage',
];

class const RunGate({
  required final String id,
  required final RunGateKind kind,
  required final RunGateStatus status,
  final String? runId,
  final String? taskId,
  final String scope = '',
  final String question = '',
  final List<String> options = const <String>[],
  final bool due = true,
  final String? resolution,
  final String? reason,
  final int? planRevision,
  final String? evidenceDigest,
  final String? integrationSha,
  final String? actorKind,
  final String? actorId,
  final DateTime? createdAt,
  final DateTime? resolvedAt,
}) {
  factory fromJson(Map<String, Object?> json) => RunGate(
    id: json.requiredString('id'),
    kind: RunGateKind.parse(json.optionalString('kind')),
    status: RunGateStatus.parse(json.optionalString('status')),
    runId: json.optionalString('runId'),
    taskId: json.optionalString('taskId'),
    scope: json.optionalString('scope') ?? '',
    question: json.optionalString('question') ?? '',
    options: json.stringList('options'),
    due: json['due'] != false,
    resolution: json.optionalString('resolution'),
    reason: json.optionalString('reason'),
    planRevision: runOptionalInt(json['planRevision']),
    evidenceDigest: json.optionalString('evidenceDigest'),
    integrationSha: json.optionalString('integrationSha'),
    actorKind: json.optionalString('actorKind'),
    actorId: json.optionalString('actorId'),
    createdAt: parseRunTimestamp(json.optionalString('createdAt')),
    resolvedAt: parseRunTimestamp(json.optionalString('resolvedAt')),
  );

  /// A person can decide it now: pending and, for a stage gate, due.
  bool get isOpen => status == RunGateStatus.pending && due;

  /// Options a person picks from. Plan, stage and stall gates always offer
  /// the runtime's fixed ids, whatever an older payload listed.
  List<String> get choices => switch (kind) {
    RunGateKind.plan || RunGateKind.stage => runReviewGateOptions,
    RunGateKind.stall => runStallGateOptions,
    _ => options,
  };

  /// Whether [decision] must carry a reason.
  static bool requiresReason(String decision) =>
      decision == 'reject' || decision == 'requestChanges';
}

class const RunTaskAttempt({
  required final String workspaceId,
  required final int attempt,
  final String? branch,
  final String? baseSha,
  final String phase = '',
}) {
  static RunTaskAttempt? tryParse(Object? value) {
    final json = asJsonMap(value);
    if (json.isEmpty) return null;
    return RunTaskAttempt(
      workspaceId: json.optionalString('workspaceId') ?? '',
      attempt: runInt(json['attempt']),
      branch: json.optionalString('branch'),
      baseSha: json.optionalString('baseSha'),
      phase: json.optionalString('phase') ?? '',
    );
  }
}

/// One task of a run, as `runs.snapshot` lists it.
class const RunTask({
  required final String id,
  required final String title,
  required final String status,
  final String? logicalId,
  final String? stageId,
  final String? roleId,
  final int? planRevision,
  final String workspaceId = '',
  final List<String> dependencies = const <String>[],
  final String? attemptState,
  final RunTaskAttempt? attempt,
  final String? integrationState,
  final String? integrationSha,
  final String? profile,
  final String? assignee,
  final DateTime? startedAt,
  final DateTime? completedAt,
  final DateTime? updatedAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    final integration = asJsonMap(json['integration']);
    return RunTask(
      id: json.requiredString('id'),
      title: json.optionalString('title') ?? json.requiredString('id'),
      status: json.optionalString('status') ?? 'pending',
      logicalId: json.optionalString('logicalId'),
      stageId: json.optionalString('stageId'),
      roleId: json.optionalString('roleId'),
      planRevision: runOptionalInt(json['planRevision']),
      workspaceId: json.optionalString('workspaceId') ?? '',
      dependencies: json.stringList('dependencies'),
      attemptState: json.optionalString('attemptState'),
      attempt: RunTaskAttempt.tryParse(json['attempt']),
      integrationState: integration.optionalString('state'),
      integrationSha: integration.optionalString('sha'),
      profile: json.optionalString('profile'),
      assignee: json.optionalString('assignee'),
      startedAt: parseRunTimestamp(json.optionalString('startedAt')),
      completedAt: parseRunTimestamp(json.optionalString('completedAt')),
      updatedAt: parseRunTimestamp(json.optionalString('updatedAt')),
    );
  }
}

class const RunPlanSummary({
  required final int revision,
  final String digest = '',
  final int? previousRevision,
  final String? changeReason,
  final String state = 'approved',
}) {
  static RunPlanSummary? tryParse(Object? value) {
    final json = asJsonMap(value);
    if (json.isEmpty) return null;
    return RunPlanSummary(
      revision: runInt(json['revision']),
      digest: json.optionalString('digest') ?? '',
      previousRevision: runOptionalInt(json['previousRevision']),
      changeReason: json.optionalString('changeReason'),
      state: json.optionalString('state') ?? 'approved',
    );
  }
}

class const RunCoordinator({
  final String? handle,
  final String? tabId,
  final String? profileId,
  final String state = 'none',
  final String? error,
}) {
  factory fromJson(Map<String, Object?> json) => RunCoordinator(
    handle: json.optionalString('handle'),
    tabId: json.optionalString('tabId'),
    profileId: json.optionalString('profileId'),
    state: json.optionalString('state') ?? 'none',
    error: json.optionalString('error'),
  );
}

class const RunCleanupSummary({
  required final String id,
  required final String state,
  final String? error,
  final bool abandoned = false,
});

/// One run with everything the detail screen shows.
class const RunDetail({
  required final RunSummary run,
  required final String objective,
  final int revision = 0,
  final bool objectiveTruncated = false,
  final int controlSequence = 0,
  final String stallPolicy = 'ask',
  final int maxConcurrent = 0,
  final String? stopReason,
  final Map<String, Object?> recipeSource = const <String, Object?>{},
  final String? sourceSha,
  final RunPlanSummary? plan,
  final RunCoordinator coordinator = const RunCoordinator(),
  final String? integrationWorkspaceId,
  final String? integrationBranch,
  final String? integrationSha,
  final List<RunGate> pendingGates = const <RunGate>[],
  final RunCleanupSummary? cleanup,

  /// Worktrees and branches still retained; null from older hosts.
  final int? resourceCount,
  final List<RunTask> tasks = const <RunTask>[],
  final String? nextTaskId,
}) {
  factory fromJson(Map<String, Object?> json) {
    final run = RunSummary.fromJson(json.mapValue('run'));
    final integration = asJsonMap(json['integration']);
    final cleanup = asJsonMap(json['cleanup']);
    return RunDetail(
      run: run,
      objective: json.optionalString('objective') ?? run.objective,
      revision: runInt(json['revision']),
      objectiveTruncated: json['objectiveTruncated'] == true,
      controlSequence: json['controlSequence'] is int
          ? json['controlSequence']! as int
          : run.controlSequence,
      stallPolicy: json.optionalString('stallPolicy') ?? 'ask',
      maxConcurrent: runInt(json['maxConcurrent']),
      stopReason: json.optionalString('stopReason'),
      recipeSource: asJsonMap(json['recipeSource']),
      sourceSha: json.optionalString('sourceSha'),
      plan: RunPlanSummary.tryParse(json['plan']),
      coordinator: RunCoordinator.fromJson(json.mapValue('coordinator')),
      integrationWorkspaceId: integration.optionalString('workspaceId'),
      integrationBranch: integration.optionalString('branch'),
      integrationSha: integration.optionalString('sha'),
      pendingGates: <RunGate>[
        for (final item in json.objectList('pendingGates'))
          RunGate.fromJson(asJsonMap(item)),
      ],
      cleanup: cleanup.optionalString('id') == null
          ? null
          : RunCleanupSummary(
              id: cleanup.requiredString('id'),
              state: cleanup.optionalString('state') ?? '',
              error: cleanup.optionalString('error'),
              abandoned: cleanup['abandoned'] == true,
            ),
      resourceCount: runOptionalInt(json['resourceCount']),
      tasks: <RunTask>[
        for (final item in json.objectList('tasks'))
          RunTask.fromJson(asJsonMap(item)),
      ],
      nextTaskId: json.optionalString('nextTaskId'),
    );
  }

  /// Name of the template the run was created from, when it names one.
  String? get recipeId => recipeSource.optionalString('id');
}
