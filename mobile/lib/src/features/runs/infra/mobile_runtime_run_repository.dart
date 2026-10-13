import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runs/domain/new_run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_cleanup_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_inspection_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_timeline_models.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

/// The runtime announces every run change, phones included.
const String runsChangedEvent = 'runsChanged';

/// Sent when a recipe is saved or a project recipe changes.
const String recipesChangedEvent = 'recipesChanged';

/// Sent when a message between agents is added, read or pruned; a run
/// timeline includes the messages of its terminals.
const String conversationsChangedEvent = 'conversationsChanged';

/// Actions on a run through `runs.control`.
enum RunControlAction { cancel, pause, resume, replan }

/// `runs.*` and the read-only `recipes.*` verbs. Every key is the runtime's
/// camelCase name: the host rejects unknown fields.
class MobileRuntimeRunRepository(final MobileRunsClient _client) {
  Stream<MobileRuntimeEvent> get changes =>
      _client.events.where((event) => event.name == runsChangedEvent);

  /// Changes a timeline shows: run events and agent messages.
  Stream<MobileRuntimeEvent> get timelineChanges => _client.events.where(
    (event) =>
        event.name == runsChangedEvent ||
        event.name == conversationsChangedEvent,
  );

  Stream<MobileRuntimeEvent> get recipeChanges =>
      _client.events.where((event) => event.name == recipesChangedEvent);

  bool get supportsRecipes => _client.supportsRecipes;

  Future<RunBoardPage> board({
    RunBucket? bucket,
    String? search,
    String? workspaceId,
    RunBoardCursor? cursor,
    int limit = 25,
  }) async {
    final query = search?.trim() ?? '';
    final payload = await _client.requestMap('runs.board', <String, Object?>{
      'bucket': ?bucket?.name,
      if (query.isNotEmpty) 'search': query,
      'workspaceId': ?workspaceId,
      'cursor': ?cursor?.toJson(),
      'limit': limit,
    });
    return RunBoardPage.fromJson(payload);
  }

  Future<RunDetail> snapshot(String runId) async => RunDetail.fromJson(
    await _client.requestMap('runs.snapshot', <String, Object?>{
      'runId': runId,
    }),
  );

  Future<RunTaskInspection> task(
    String runId,
    String taskId, {
    Map<String, Object?>? cursor,
  }) async => RunTaskInspection.fromJson(
    await _client.requestMap('runs.task', <String, Object?>{
      'runId': runId,
      'taskId': taskId,
      'cursor': ?cursor,
    }),
  );

  Future<RunTimelinePage> timeline(
    String runId, {
    String? cursor,
    String? taskId,
    int limit = 50,
  }) async => RunTimelinePage.fromJson(
    await _client.requestMap('runs.timeline', <String, Object?>{
      'runId': runId,
      'cursor': ?cursor,
      'taskId': ?taskId,
      'limit': limit,
    }),
  );

  Future<RunPlanView?> plan(String runId) async {
    final payload = await _client.requestMap('runs.plan', <String, Object?>{
      'runId': runId,
    });
    return RunPlanView.tryParse(payload['plan']);
  }

  Future<RunGateDetail> gate(String gateId) async => RunGateDetail.fromJson(
    await _client.requestMap('runs.gate', <String, Object?>{'gateId': gateId}),
  );

  /// Decides [gate]. The evidence digest it was shown with travels along, so
  /// the runtime refuses a decision on evidence that changed since.
  Future<RunGateResolution> resolveGate({
    required String requestId,
    required RunGate gate,
    required String decision,
    String? reason,
  }) async {
    final note = reason?.trim() ?? '';
    final payload = await _client.requestMap(
      'runs.resolveGate',
      <String, Object?>{
        'requestId': requestId,
        'gateId': gate.id,
        'decision': decision,
        if (note.isNotEmpty) 'reason': note,
        'expectedEvidenceDigest': ?gate.evidenceDigest,
      },
    );
    return RunGateResolution.fromJson(payload);
  }

  Future<Map<String, Object?>> control({
    required String requestId,
    required String runId,
    required int expectedSequence,
    required RunControlAction action,
    String? reason,
  }) {
    final note = reason?.trim() ?? '';
    return _client.requestMap('runs.control', <String, Object?>{
      'requestId': requestId,
      'runId': runId,
      'expectedSequence': expectedSequence,
      'action': action.name,
      if (note.isNotEmpty) 'reason': note,
    });
  }

  Future<Map<String, Object?>> retryTask({
    required String requestId,
    required String runId,
    required String taskId,
  }) => _client.requestMap('runs.retryTask', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'taskId': taskId,
  });

  Future<Map<String, Object?>> retryIntegration({
    required String requestId,
    required String runId,
    required String taskId,
  }) => _client.requestMap('runs.retryIntegration', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'taskId': taskId,
  });

  Future<Map<String, Object?>> retryCancellation({
    required String requestId,
    required String runId,
    required int expectedSequence,
  }) => _client.requestMap('runs.retryCancellation', <String, Object?>{
    'requestId': requestId,
    'runId': runId,
    'expectedSequence': expectedSequence,
  });

  Future<RunResourcePage> resources(String runId, {int? beforeRow}) async =>
      RunResourcePage.fromJson(
        await _client.requestMap('runs.resources', <String, Object?>{
          'runId': runId,
          'beforeRow': ?beforeRow,
        }),
      );

  Future<List<RunCleanupHistoryEntry>> cleanups(String runId) async {
    final payload = await _client.requestMap('runs.cleanups', <String, Object?>{
      'runId': runId,
    });
    return <RunCleanupHistoryEntry>[
      for (final item in payload.objectList('items'))
        RunCleanupHistoryEntry.fromJson(asJsonMap(item)),
    ];
  }

  /// Inspects the selection without removing anything.
  Future<RunCleanupPreview> previewCleanup({
    required String id,
    required String runId,
    required List<RunCleanupSelection> resources,
  }) async => RunCleanupPreview.fromJson(
    await _client.requestMap('runs.previewCleanup', <String, Object?>{
      'id': id,
      'runId': runId,
      'resources': <Map<String, Object?>>[
        for (final resource in resources) resource.toJson(),
      ],
    }),
  );

  Future<RunCleanupStatus> cleanup(String id) async =>
      RunCleanupStatus.fromJson(
        await _client.requestMap('runs.cleanup', <String, Object?>{'id': id}),
      );

  /// Removes exactly what [preview] showed. `confirm: true` is the runtime's
  /// guard that a person reviewed it.
  Future<Map<String, Object?>> applyCleanup(RunCleanupPreview preview) =>
      _client.requestMap('runs.applyCleanup', <String, Object?>{
        'id': preview.id,
        'digest': preview.digest,
        'confirm': true,
      });

  Future<Map<String, Object?>> retryCleanup(RunCleanupPreview preview) =>
      _client.requestMap('runs.retryCleanup', <String, Object?>{
        'id': preview.id,
        'digest': preview.digest,
      });

  Future<Map<String, Object?>> abandonCleanup(RunCleanupPreview preview) =>
      _client.requestMap('runs.abandonCleanup', <String, Object?>{
        'id': preview.id,
        'digest': preview.digest,
      });

  Future<RunSourceSnapshot> source(String workspaceId) async =>
      RunSourceSnapshot.fromJson(
        await _client.requestMap('runs.source', <String, Object?>{
          'workspaceId': workspaceId,
        }),
      );

  Future<NewRunResult> create(NewRunRequest request) async =>
      NewRunResult.fromJson(
        await _client.requestMap('runs.create', request.toJson()),
      );

  /// Templates for New Run. Without `recipesV1` only the built-in default is
  /// known, which isolated runs use when no recipe is named.
  Future<RecipeCatalog> recipeCatalog({String? workspaceId}) async {
    if (!_client.supportsRecipes) return const RecipeCatalog();
    return RecipeCatalog.fromJson(
      await _client.requestMap('recipes.catalog', <String, Object?>{
        'workspaceId': ?workspaceId,
      }),
    );
  }

  Future<List<WorkspaceSummary>> workspaces() => _client.listWorkspaces();

  Future<List<AgentProfileSummary>> agentProfiles() =>
      _client.listAgentProfiles();
}
