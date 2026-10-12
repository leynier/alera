import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:alera/src/features/runs/domain/run_task_inspection.dart';
import 'package:alera/src/features/runs/domain/run_timeline.dart';

/// The fixed "now" every Runs test measures ages against.
final DateTime runsTestNow = DateTime.utc(2026, 9, 30, 14, 10);

Map<String, Object?> runSummaryJson({
  String id = 'run-1',
  String objective = 'Add OAuth login to the settings page',
  String status = 'paused',
  String bucket = 'attention',
  String isolation = 'isolated',
  List<String> pendingGateKinds = const <String>['stage'],
  bool planGatePending = false,
  int taskCount = 9,
  int completedCount = 4,
  int stalledCount = 0,
  int pendingGateCount = 1,
  String lastActivityAt = '2026-09-30T12:10:00Z',
  String? completedAt,
  int controlSequence = 3,
  String workspaceName = 'feature-oauth',
  String projectName = 'alera',
  List<Map<String, Object?>>? pendingGates,
}) => <String, Object?>{
  'id': id,
  'objective': objective,
  'status': status,
  'bucket': bucket,
  'workspaceId': 'ws-1',
  'workspaceName': workspaceName,
  'projectId': 'project-1',
  'projectName': projectName,
  'createdAt': '2026-09-30T10:00:00Z',
  'lastActivityAt': lastActivityAt,
  'completedAt': completedAt,
  'planGatePending': planGatePending,
  'isolation': isolation,
  'approvalRequired': true,
  'planRevision': 2,
  'attentionReason': null,
  'coordinatorState': 'started',
  'pausedBy': status == 'paused' ? 'runtime' : null,
  'controlSequence': controlSequence,
  'pendingGateKinds': pendingGateKinds,
  'taskCount': taskCount,
  'completedCount': completedCount,
  'runningCount': 1,
  'failedCount': 0,
  'stalledCount': stalledCount,
  'blockedCount': 0,
  'pendingGateCount': pendingGateCount,
  'cleanupAttention': false,
  'cleanupApplying': false,
  'pendingGates': ?pendingGates,
};

RunSummary runSummary({
  String id = 'run-1',
  String objective = 'Add OAuth login to the settings page',
  String status = 'paused',
  String bucket = 'attention',
  String isolation = 'isolated',
  List<String> pendingGateKinds = const <String>['stage'],
  bool planGatePending = false,
  int stalledCount = 0,
  int completedCount = 4,
  String lastActivityAt = '2026-09-30T12:10:00Z',
  String? completedAt,
  List<Map<String, Object?>>? pendingGates,
}) => RunSummary.fromJson(
  runSummaryJson(
    pendingGates: pendingGates,
    id: id,
    objective: objective,
    status: status,
    bucket: bucket,
    isolation: isolation,
    pendingGateKinds: pendingGateKinds,
    planGatePending: planGatePending,
    stalledCount: stalledCount,
    completedCount: completedCount,
    lastActivityAt: lastActivityAt,
    completedAt: completedAt,
  ),
);

RunBoardPage runsBoardPage({List<RunSummary>? items, bool more = false}) =>
    RunBoardPage(
      revision: 7,
      counts: const RunBoardCounts(attention: 2, active: 1, history: 1),
      items:
          items ??
          <RunSummary>[
            runSummary(),
            runSummary(
              id: 'run-2',
              objective: 'Migrate CI to Actions',
              status: 'running',
              isolation: 'shared',
              pendingGateKinds: const <String>['stall'],
              stalledCount: 1,
              completedCount: 2,
              lastActivityAt: '2026-09-30T13:50:00Z',
            ),
            runSummary(
              id: 'run-3',
              objective: 'Refactor quota parser',
              status: 'running',
              bucket: 'active',
              pendingGateKinds: const <String>[],
              completedCount: 1,
              lastActivityAt: '2026-09-30T14:00:00Z',
            ),
            runSummary(
              id: 'run-4',
              objective: 'Rename packages',
              status: 'completed',
              bucket: 'history',
              pendingGateKinds: const <String>[],
              completedCount: 9,
              lastActivityAt: '2026-09-29T09:00:00Z',
              completedAt: '2026-09-29T09:00:00Z',
            ),
          ],
      nextCursor: more
          ? const RunBoardCursor(
              createdAt: '2026-09-29T00:00:00Z',
              id: 'run-4',
              revision: 7,
            )
          : null,
    );

Map<String, Object?> runGateJson({
  String id = 'gate-stage',
  String kind = 'stage',
  String? taskId,
  String scope = 'foundation',
  String question = '',
  List<String>? options,
  String status = 'pending',
  bool due = true,
  String? evidenceDigest = 'digest-1',
  int? planRevision = 2,
  String createdAt = '2026-09-30T13:58:00Z',
}) => <String, Object?>{
  'id': id,
  'runId': 'run-1',
  'taskId': taskId,
  'kind': kind,
  'scope': scope,
  'question': question,
  'options':
      options ??
      switch (kind) {
        'stall' => RunGateOptions.stall,
        'decision' => const <String>[],
        _ => RunGateOptions.review,
      },
  'status': status,
  'due': due,
  'resolution': null,
  'reason': null,
  'planRevision': planRevision,
  'evidenceDigest': evidenceDigest,
  'integrationSha': kind == 'stage' ? 'd4e5f6a7b8c9' : null,
  'actorKind': null,
  'actorId': null,
  'createdAt': createdAt,
  'resolvedAt': null,
};

RunGate runGate({
  String id = 'gate-stage',
  String kind = 'stage',
  String? taskId,
  String scope = 'foundation',
  String question = '',
  List<String>? options,
  bool due = true,
  String? evidenceDigest = 'digest-1',
  String createdAt = '2026-09-30T13:58:00Z',
}) => RunGate.fromJson(
  runGateJson(
    id: id,
    kind: kind,
    taskId: taskId,
    scope: scope,
    question: question,
    options: options,
    due: due,
    evidenceDigest: evidenceDigest,
    createdAt: createdAt,
  ),
);

Map<String, Object?> runTaskJson({
  String id = 'task-1',
  String logicalId = 'scaffold-provider',
  String title = 'Scaffold the provider',
  String status = 'completed',
  String stageId = 'foundation',
  String? attemptState = 'integrated',
  int attempt = 1,
}) => <String, Object?>{
  'id': id,
  'logicalId': logicalId,
  'title': title,
  'status': status,
  'stageId': stageId,
  'roleId': 'worker',
  'planRevision': 2,
  'workspaceId': 'ws-$id',
  'dependencies': const <String>[],
  'dependenciesTruncated': false,
  'attemptState': attemptState,
  'attempt': <String, Object?>{
    'workspaceId': 'ws-$id',
    'attempt': attempt,
    'branch': 'alera/runs/run-1/$logicalId',
    'baseSha': 'a1b2c3d4e5f6',
    'phase': 'ready',
  },
  'integration': attemptState == 'integrated'
      ? <String, Object?>{'state': 'integrated', 'sha': '9f8e7d6c5b4a'}
      : null,
  'profile': 'Codex Sol',
  'assignee': 'w-1',
};

RunSnapshot runSnapshot({
  RunSummary? run,
  List<RunGate>? gates,
  String? planState = 'approved',
  String coordinatorState = 'started',
  String? coordinatorError,
  bool moreTasks = false,
}) => RunSnapshot.fromJson(<String, Object?>{
  'revision': 7,
  'run': (run ?? runSummary()).toMap(),
  'objective': 'Add OAuth login (Google, GitHub) to Settings > Account. Keep the existing email flow working.',
  'objectiveTruncated': false,
  'controlSequence': (run ?? runSummary()).controlSequence,
  'stallPolicy': 'ask',
  'maxConcurrent': 4,
  'stopReason': null,
  'recipeSource': <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
  'sourceSha': 'a1b2c3d4e5f6',
  'plan': planState == null
      ? null
      : <String, Object?>{
          'revision': 2,
          'digest': 'plan-digest',
          'previousRevision': 1,
          'changeReason': null,
          'state': planState,
        },
  'coordinator': <String, Object?>{
    'handle': 'coordinator-1',
    'tabId': 'tab-coordinator',
    'profileId': 'codex-sol',
    'state': coordinatorState,
    'error': coordinatorError,
  },
  'integration': <String, Object?>{
    'workspaceId': 'ws-integration',
    'branch': 'alera/runs/run-1',
    'sha': 'd4e5f6a7b8c9',
  },
  'pendingGates': <Object?>[
    for (final gate in gates ?? <RunGate>[runGate()]) gate.toMap(),
  ],
  'cleanup': null,
  'tasks': <Object?>[
    runTaskJson(),
    runTaskJson(
      id: 'task-2',
      logicalId: 'implement-github',
      title: 'Implement GitHub provider',
      status: 'stalled',
      stageId: 'implementation',
      attemptState: 'stalled',
      attempt: 2,
    ),
    runTaskJson(
      id: 'task-3',
      logicalId: 'add-oauth-config',
      title: 'Add OAuth config',
      status: 'dispatched',
      stageId: 'implementation',
      attemptState: 'started',
    ),
  ],
  'nextTaskId': moreTasks ? 'task-3' : null,
});

TaskInspection taskInspection({
  String taskId = 'task-2',
  List<RunGate>? gates,
  bool canRetry = true,
  bool moreHistory = false,
}) => TaskInspection.fromJson(<String, Object?>{
  'revision': 7,
  'taskId': taskId,
  'runId': 'run-1',
  'title': 'Implement GitHub provider',
  'description': 'Implement the GitHub OAuth provider behind the existing provider interface.',
  'descriptionTruncated': false,
  'status': 'stalled',
  'stageId': 'implementation',
  'workspaceId': 'ws-1',
  'workspaceName': 'feature-oauth',
  'workspacePath': '/projects/alera',
  'branch': null,
  'baseSha': null,
  'profile': 'Codex Sol (codex)',
  'terminalHandle': 'w-3',
  'dependencies': const <String>['scaffold-provider', 'add-oauth-config'],
  'dependenciesTruncated': false,
  'result': <String, Object?>{
    'summary': null,
    'completionKind': null,
    'artifacts': const <String>[],
    'validation': const <String>[],
    'preview': null,
    'truncated': false,
  },
  'history': <Object?>[
    <String, Object?>{
      'id': 'h-2',
      'occurredAt': '2026-09-30T14:02:00Z',
      'kind': 'attempt',
      'status': 'stalled',
      'summary': 'Lease expired after 10m',
    },
    <String, Object?>{
      'id': 'h-1',
      'occurredAt': '2026-09-30T13:10:00Z',
      'kind': 'attempt',
      'status': 'failed',
      'summary': 'Startup failed: codex: command not found',
    },
  ],
  'nextCursor': moreHistory
      ? <String, Object?>{
          'occurredAt': '2026-09-30T13:10:00Z',
          'id': 'h-1',
          'revision': 7,
        }
      : null,
  'attempt': <String, Object?>{
    'planRevision': 2,
    'attempt': 2,
    'phase': 'attention',
    'canRetry': canRetry,
    'canRetryIntegration': false,
    'state': 'stalled',
    'executionWorkspaceId': 'ws-1',
    'worktree': '/home/user/.alera/worktrees/alera/run-1/implement-github',
    'branch': 'alera/runs/run-1/implement-github',
    'baseSha': 'a1b2c3d4e5f6',
    'conflictPaths': const <String>[],
    'conflictsTruncated': false,
  },
  'gates': <Object?>[
    for (final gate
        in gates ??
            <RunGate>[
              runGate(
                id: 'gate-stall',
                kind: 'stall',
                taskId: taskId,
                question: 'Worker w-3 has shown no activity since 14:02. It may still be running, so Alera will not respawn it without a decision.',
              ),
            ])
      gate.toMap(),
  ],
  'logicalId': 'implement-github',
  'planRevision': 2,
  'roleId': 'worker',
});

RunTimelineEntry timelineEntry({
  required String id,
  String source = 'event',
  required String kind,
  required String createdAt,
  String summary = '',
  String? gateId,
  String? from,
  String? to,
  String? body,
  String? messageType,
  String? actorKind,
  String? actorId,
}) => RunTimelineEntry(
  id: id,
  source: source,
  kind: kind,
  createdAt: createdAt,
  summary: summary,
  gateId: gateId,
  from: from,
  to: to,
  body: body,
  messageType: messageType,
  actorKind: actorKind,
  actorId: actorId,
);

RunTimelinePage runTimelinePage({String? cursor}) => cursor == null
    ? RunTimelinePage(
        runId: 'run-1',
        items: <RunTimelineEntry>[
          timelineEntry(
            id: 'e-5',
            kind: 'gateOpened',
            createdAt: '2026-09-30T13:58:30Z',
            summary: 'Stage gate on foundation',
            gateId: 'gate-stage',
          ),
          timelineEntry(
            id: 'e-escalation',
            kind: 'escalation',
            createdAt: '2026-09-30T13:58:00Z',
            summary: 'GitHub OAuth app secret is missing',
            actorKind: 'agent',
            actorId: 'w-3',
            from: 'w-3',
            to: 'coordinator-1',
            body: 'GitHub OAuth app secret is missing.\nI need the secret name before wiring the callback.',
            messageType: 'escalation',
          ),
          timelineEntry(
            id: 'e-4',
            kind: 'dispatched',
            createdAt: '2026-09-30T13:40:00Z',
            summary: 'implement-github to w-3 (Codex Sol)',
          ),
          timelineEntry(
            id: 'e-3',
            kind: 'integrated',
            createdAt: '2026-09-30T13:35:00Z',
            summary: 'scaffold-provider at 9f8e7d6',
          ),
        ],
        nextCursor: '2026-09-30T13:35:00Z|e-3',
      )
    : RunTimelinePage(
        runId: 'run-1',
        items: <RunTimelineEntry>[
          timelineEntry(
            id: 'e-2',
            kind: 'planApproved',
            createdAt: '2026-09-29T18:30:00Z',
            summary: 'Revision 1',
            actorKind: 'desktop',
          ),
          timelineEntry(
            id: 'e-1',
            kind: 'created',
            createdAt: '2026-09-29T17:58:00Z',
            summary: 'Feature Delivery from a1b2c3d',
          ),
        ],
      );
