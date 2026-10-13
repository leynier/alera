import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

typedef RunsCall = ({String type, Map<String, Object?> payload});

Map<String, Object?> runSummaryJson({
  String id = 'run-1',
  String objective = 'Add OAuth login to the web app',
  String status = 'running',
  String bucket = 'active',
  String isolation = 'isolated',
  int pendingGateCount = 0,
  List<String> pendingGateKinds = const <String>[],
  int taskCount = 9,
  int completedCount = 4,
  int stalledCount = 0,
  int controlSequence = 3,
  String? completedAt,
  bool planGatePending = false,
}) => <String, Object?>{
  'id': id,
  'objective': objective,
  'status': status,
  'bucket': bucket,
  'workspaceId': 'ws-1',
  'workspaceName': 'feature-oauth',
  'projectId': 'p-1',
  'projectName': 'alera',
  'createdAt': '2026-10-11T08:00:00Z',
  'lastActivityAt': '2026-10-11T09:00:00Z',
  'completedAt': completedAt,
  'planGatePending': planGatePending,
  'isolation': isolation,
  'approvalRequired': false,
  'planRevision': 2,
  'attentionReason': null,
  'coordinatorState': 'started',
  'pausedBy': null,
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
};

Map<String, Object?> runGateJson({
  String id = 'gate-1',
  String kind = 'stage',
  String status = 'pending',
  String scope = 'foundation',
  String question = '',
  List<String>? options,
  String? taskId,
  String? evidenceDigest = 'sha256:evidence',
  bool due = true,
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
        'stall' => <String>['killAndFailover', 'keepWaiting', 'abortStage'],
        'decision' => <String>[],
        _ => <String>['approve', 'requestChanges', 'reject'],
      },
  'status': status,
  'due': due,
  'resolution': null,
  'reason': null,
  'planRevision': 2,
  'evidenceDigest': evidenceDigest,
  'integrationSha': '4f2a91c07d11',
  'actorKind': null,
  'actorId': null,
  'createdAt': '2026-10-11T09:00:00Z',
  'resolvedAt': null,
};

Map<String, Object?> runTaskJson({
  String id = 'task-1',
  String title = 'Add the OAuth callback',
  String status = 'dispatched',
  String? attemptState = 'started',
}) => <String, Object?>{
  'id': id,
  'logicalId': id,
  'title': title,
  'status': status,
  'stageId': 'foundation',
  'roleId': 'worker',
  'planRevision': 2,
  'workspaceId': 'ws-1',
  'dependencies': <String>[],
  'dependenciesTruncated': false,
  'attemptState': attemptState,
  'attempt': null,
  'integration': null,
  'profile': 'codex',
  'assignee': 'Codex',
};

Map<String, Object?> runSnapshotJson({
  Map<String, Object?>? run,
  List<Map<String, Object?>> pendingGates = const <Map<String, Object?>>[],
  List<Map<String, Object?>>? tasks,
}) {
  final summary = run ?? runSummaryJson();
  return <String, Object?>{
    'revision': 10,
    'run': summary,
    'objective': summary['objective'],
    'objectiveTruncated': false,
    'controlSequence': summary['controlSequence'],
    'stallPolicy': 'ask',
    'maxConcurrent': 4,
    'stopReason': null,
    'recipeSource': <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
    'sourceSha': 'abc123',
    'plan': <String, Object?>{
      'revision': 2,
      'digest': 'd',
      'previousRevision': 1,
      'changeReason': null,
      'state': 'approved',
    },
    'coordinator': <String, Object?>{
      'handle': 'coord',
      'tabId': 'tab-c',
      'profileId': 'codex',
      'state': 'started',
      'error': null,
    },
    'integration': null,
    'pendingGates': pendingGates,
    'cleanup': null,
    'tasks': tasks ?? <Map<String, Object?>>[runTaskJson()],
    'nextTaskId': null,
  };
}

Map<String, Object?> runTimelineEntryJson(
  String id, {
  String kind = 'dispatched',
}) => <String, Object?>{
  'id': id,
  'source': 'event',
  'kind': kind,
  'createdAt': '2026-10-11T09:00:00Z',
  'taskId': null,
  'dispatchId': null,
  'gateId': null,
  'actorKind': 'runtime',
  'actorId': null,
  'summary': 'Event $id',
  'payload': null,
  'messageType': null,
  'from': null,
  'to': null,
  'threadId': null,
  'body': null,
  'truncated': false,
};

Map<String, Object?> runResourceJson(String workspaceId, {String? branch}) =>
    <String, Object?>{
      'identity': <String, Object?>{
        'workspace': <String, Object?>{
          'id': workspaceId,
          'name': 'attempt-$workspaceId',
          'branch': branch ?? 'alera/runs/$workspaceId',
          'path': '/tmp/$workspaceId',
        },
        'repoPath': '/repo',
        'ownerWorkspaceId': 'ws-1',
        'runId': 'run-1',
        'revision': 2,
        'taskId': 'task-1',
        'attempt': 1,
        'baseSha': 'abc',
      },
      'phase': 'retained',
      'registered': true,
      'cleanupId': null,
      'cleanupState': null,
      'retired': false,
    };

/// Paired runtime double for the run screens. Responses are the JSON the
/// runtime sends; [failures] makes a verb fail with a runtime error code.
class FakeRunsClient implements MobileRunsClient {
  FakeRunsClient({this.supportsRuns = true, this.supportsRecipes = true});

  @override
  bool supportsRuns;

  @override
  bool supportsRecipes;

  List<Map<String, Object?>> runs = <Map<String, Object?>>[
    runSummaryJson(
      id: 'run-a',
      objective: 'Fix flaky login test',
      status: 'paused',
      bucket: 'attention',
      pendingGateCount: 1,
      pendingGateKinds: <String>['stage'],
    ),
    runSummaryJson(id: 'run-b', objective: 'Migrate CI to Actions'),
    runSummaryJson(
      id: 'run-c',
      objective: 'Write release notes',
      status: 'completed',
      bucket: 'history',
      completedAt: '2026-10-10T09:00:00Z',
    ),
  ];
  Map<String, Map<String, Object?>> snapshots =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> gates = <String, Map<String, Object?>>{};
  List<Map<String, Object?>> timeline = <Map<String, Object?>>[
    for (var index = 0; index < 3; index++) runTimelineEntryJson('e$index'),
  ];
  int timelinePageSize = 2;
  List<Map<String, Object?>> resources = <Map<String, Object?>>[
    runResourceJson('attempt-1'),
  ];
  Map<String, RuntimeRequestError> failures = <String, RuntimeRequestError>{};
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[
    WorkspaceSummary(
      id: 'ws-1',
      projectId: 'p-1',
      name: 'feature-oauth',
      path: '/w',
    ),
  ];
  List<AgentProfileSummary> profiles = const <AgentProfileSummary>[
    AgentProfileSummary(id: 'codex', name: 'Codex', agentType: 'codex'),
    AgentProfileSummary(id: 'claude', name: 'Claude', agentType: 'claude'),
  ];

  final List<RunsCall> calls = <RunsCall>[];
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();

  Iterable<RunsCall> callsOf(String type) =>
      calls.where((call) => call.type == type);

  void emit(String name, [Map<String, Object?> payload = const {}]) =>
      _events.add(MobileRuntimeEvent(name, payload));

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaces;

  @override
  Future<List<AgentProfileSummary>> listAgentProfiles() async => profiles;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add((type: type, payload: payload));
    if (failures.remove(type) case final failure?) throw failure;
    return switch (type) {
      'runs.board' => _board(payload),
      'runs.snapshot' =>
        snapshots[payload['runId']] ??
            runSnapshotJson(
              run: runs.firstWhere((run) => run['id'] == payload['runId']),
            ),
      'runs.gate' => <String, Object?>{
        'gate':
            gates[payload['gateId']] ?? runGateJson(id: '${payload['gateId']}'),
        'plan': null,
        'tasks': <Object?>[],
      },
      'runs.resolveGate' => <String, Object?>{
        'requestId': payload['requestId'],
        'gate': <String, Object?>{
          ...gates[payload['gateId']] ??
              runGateJson(id: '${payload['gateId']}'),
          'status': 'resolved',
          'resolution': payload['decision'],
        },
        'runId': 'run-1',
        'runStatus': 'running',
        'planRevision': 2,
        'changesRequested': payload['decision'] == 'requestChanges',
        'coordinatorAction': 'none',
      },
      'runs.control' => <String, Object?>{
        'requestId': payload['requestId'],
        'runId': payload['runId'],
        'action': payload['action'],
        'sequence': 4,
        'status': 'paused',
      },
      'runs.timeline' => _timeline(payload),
      'runs.resources' => <String, Object?>{
        'runId': payload['runId'],
        'revision': 1,
        'items': resources,
        'nextBeforeRow': null,
      },
      'runs.cleanups' => <String, Object?>{
        'runId': payload['runId'],
        'revision': 1,
        'items': <Object?>[],
        'nextBeforeRow': null,
      },
      'runs.previewCleanup' => _preview(payload),
      'runs.applyCleanup' => <String, Object?>{'id': payload['id']},
      'runs.cleanup' => <String, Object?>{
        'preview': _preview(<String, Object?>{
          'id': payload['id'],
          'runId': 'run-1',
          'resources': <Object?>[
            <String, Object?>{'workspaceId': 'attempt-1', 'removeBranch': true},
          ],
        }),
        'state': 'retired',
        'error': null,
        'retiredWorkspaceIds': <String>['attempt-1'],
      },
      'runs.source' => <String, Object?>{
        'workspace': <String, Object?>{'workspaceId': payload['workspaceId']},
        'sha': 'abcdef1234',
        'hasUncommittedChanges': false,
      },
      'runs.create' => <String, Object?>{
        'run': <String, Object?>{
          'runId': 'run-new',
          'status': 'planning',
          'isolation': payload['isolation'],
          'coordinatorTabId': 'tab-c',
          'coordinatorProfileId': payload['coordinatorProfileId'],
        },
        'coordinator': <String, Object?>{'status': 'started'},
      },
      'recipes.catalog' => <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'source': <String, Object?>{'origin': 'builtIn', 'id': 'freeform'},
            'name': 'Freeform',
          },
          <String, Object?>{
            'source': <String, Object?>{
              'origin': 'builtIn',
              'id': 'feature-delivery',
            },
            'name': 'Feature Delivery',
          },
        ],
        'projectError': null,
      },
      _ => <String, Object?>{},
    };
  }

  Map<String, Object?> _board(Map<String, Object?> payload) {
    final matching = <Map<String, Object?>>[
      for (final run in runs)
        if (payload['bucket'] == null || run['bucket'] == payload['bucket'])
          run,
    ];
    int count(String bucket) =>
        runs.where((run) => run['bucket'] == bucket).length;
    return <String, Object?>{
      'revision': 1,
      'counts': <String, Object?>{
        'attention': count('attention'),
        'active': count('active'),
        'history': count('history'),
      },
      'items': matching,
      'nextCursor': null,
    };
  }

  Map<String, Object?> _timeline(Map<String, Object?> payload) {
    final start = payload['cursor'] == null
        ? 0
        : int.parse('${payload['cursor']}'.split(':').last);
    final end = (start + timelinePageSize).clamp(0, timeline.length);
    return <String, Object?>{
      'runId': payload['runId'],
      'items': timeline.sublist(start, end),
      'nextCursor': end < timeline.length ? 'at:$end' : null,
    };
  }

  Map<String, Object?> _preview(Map<String, Object?> payload) =>
      <String, Object?>{
        'id': payload['id'],
        'runId': payload['runId'],
        'digest': 'sha256:preview',
        'expiresAt': 0,
        'items': <Object?>[
          for (final selection
              in (payload['resources']! as List<Object?>)
                  .cast<Map<String, Object?>>())
            <String, Object?>{
              'identity': runResourceJson(
                selection['workspaceId']! as String,
              )['identity'],
              'git': <String, Object?>{
                'headSha': 'abc',
                'dirty': true,
                'operationInProgress': false,
                'locked': false,
                'changedPaths': <String>['lib/a.dart'],
                'pathsTruncated': false,
              },
              'removeBranch': selection['removeBranch'],
            },
        ],
      };
}
