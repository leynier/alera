import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'run_actions.g.dart';

/// Busy, error and stale flags of run mutations, keyed by what they act on
/// (see [RunActions.gateKey], [RunActions.runKey], [RunActions.taskKey]).
class const RunActionsState({
  final Map<String, String> busy = const <String, String>{},
  final Map<String, Object> errors = const <String, Object>{},
  final Set<String> staleGates = const <String>{},
}) {
  /// The action running for [key], such as `approve` or `pause`.
  String? busyFor(String key) => busy[key];

  Object? errorFor(String key) => errors[key];

  bool isStale(String gateId) => staleGates.contains(gateId);

  RunActionsState _with({
    Map<String, String>? busy,
    Map<String, Object>? errors,
    Set<String>? staleGates,
  }) => RunActionsState(
    busy: busy ?? this.busy,
    errors: errors ?? this.errors,
    staleGates: staleGates ?? this.staleGates,
  );
}

/// Every run mutation goes through here. A retry of the same action reuses
/// its request id, so a response lost in transit replays the stored receipt
/// instead of acting twice. Holds no subscriptions, only these flags.
@Riverpod(keepAlive: true)
class RunActions extends _$RunActions {
  final Map<String, String> _requestIds = <String, String>{};

  /// A fresh client request id for a mutation the caller tracks itself.
  static String newRequestId() => const Uuid().v4();

  static String gateKey(String gateId) => 'gate:$gateId';
  static String runKey(String runId) => 'run:$runId';
  static String taskKey(String taskId) => 'task:$taskId';
  static const String createKey = 'create';

  @override
  RunActionsState build() => const RunActionsState();

  String _requestId(String operation) =>
      _requestIds.putIfAbsent(operation, newRequestId);

  Future<T?> _run<T>(
    String key,
    String label,
    String operation,
    Future<T> Function(String requestId) action, {
    String? gateId,
  }) async {
    if (state.busy.containsKey(key)) return null;
    state = state._with(
      busy: <String, String>{...state.busy, key: label},
      errors: <String, Object>{...state.errors}..remove(key),
    );
    try {
      final result = await action(_requestId(operation));
      _requestIds.remove(operation);
      if (ref.mounted) {
        state = state._with(
          busy: <String, String>{...state.busy}..remove(key),
          staleGates: gateId == null
              ? null
              : (<String>{...state.staleGates}..remove(gateId)),
        );
      }
      return result;
    } on Object catch (error) {
      final stale = isRunStaleError(error);
      // A stale decision is never replayed: the next one is about new state.
      if (stale) _requestIds.remove(operation);
      if (ref.mounted) {
        state = state._with(
          busy: <String, String>{...state.busy}..remove(key),
          errors: stale ? null : <String, Object>{...state.errors, key: error},
          staleGates: stale && gateId != null
              ? <String>{...state.staleGates, gateId}
              : null,
        );
      }
      return null;
    }
  }

  /// Forgets a stale flag once the user refreshed the gate.
  void clearGate(String gateId) {
    state = state._with(
      staleGates: <String>{...state.staleGates}..remove(gateId),
      errors: <String, Object>{...state.errors}..remove(gateKey(gateId)),
    );
  }

  void clearError(String key) => state = state._with(
    errors: <String, Object>{...state.errors}..remove(key),
  );

  /// Creates a run. [RunCreateRequest.requestId] is the caller's, so a
  /// retried submit of the same form replays the same run.
  Future<RunCreateResult?> create(RunCreateRequest request) => _run(
    createKey,
    'create',
    'create:${request.requestId}',
    (_) => ref.read(runRepositoryProvider).create(request),
  );

  /// Resolves [gate] with an option id (or free text for decision gates).
  /// Returns whether the runtime accepted it.
  Future<bool> resolveGate(
    RunGate gate,
    String decision, {
    String? reason,
    List<String>? taskIds,
  }) async {
    final note = reason?.trim();
    final receipt = await _run(
      gateKey(gate.id),
      decision,
      'gate:${gate.id}:$decision:${note ?? ''}:${gate.evidenceDigest ?? ''}',
      (requestId) => ref
          .read(runRepositoryProvider)
          .resolveGate(
            requestId: requestId,
            gateId: gate.id,
            decision: decision,
            reason: note == null || note.isEmpty ? null : note,
            taskIds: taskIds,
            expectedEvidenceDigest: gate.evidenceDigest,
          ),
      gateId: gate.id,
    );
    return receipt != null;
  }

  /// Pause, resume, cancel or replan against the sequence [snapshot] showed.
  Future<RunControlReceipt?> control(
    RunSnapshot snapshot,
    RunControlAction action, {
    String? reason,
  }) {
    final runId = snapshot.run.id;
    final sequence = snapshot.controlSequence;
    return _run(
      runKey(runId),
      action.name,
      'control:$runId:${action.name}:$sequence:${reason ?? ''}',
      (requestId) => ref
          .read(runRepositoryProvider)
          .control(
            requestId: requestId,
            runId: runId,
            expectedSequence: sequence,
            action: action,
            reason: reason,
          ),
    );
  }

  Future<bool> retryTask(String runId, String taskId) async =>
      await _run(
        taskKey(taskId),
        'retryTask',
        'retryTask:$runId:$taskId',
        (requestId) => ref
            .read(runRepositoryProvider)
            .retryTask(requestId: requestId, runId: runId, taskId: taskId),
      ) !=
      null;

  Future<bool> retryIntegration(String runId, String taskId) async =>
      await _run(
        taskKey(taskId),
        'retryIntegration',
        'retryIntegration:$runId:$taskId',
        (requestId) => ref
            .read(runRepositoryProvider)
            .retryIntegration(
              requestId: requestId,
              runId: runId,
              taskId: taskId,
            ),
      ) !=
      null;

  Future<bool> retryCancellation(RunSnapshot snapshot) async {
    final runId = snapshot.run.id;
    final sequence = snapshot.controlSequence;
    return await _run(
          runKey(runId),
          'retryCancellation',
          'retryCancellation:$runId:$sequence',
          (requestId) => ref
              .read(runRepositoryProvider)
              .retryCancellation(
                requestId: requestId,
                runId: runId,
                expectedSequence: sequence,
              ),
        ) !=
        null;
  }
}
