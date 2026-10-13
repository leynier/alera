import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_inspection_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/infra/mobile_runtime_run_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'mobile_run_actions.g.dart';

/// Which actions of a run are in flight, and which gates went stale under
/// the user.
class const MobileRunActionState({
  final Set<String> busy = const <String>{},
  final Set<String> staleGateIds = const <String>{},
}) {
  bool isBusy(String key) => busy.contains(key);

  bool get anyBusy => busy.isNotEmpty;
}

/// Busy key of a gate decision.
String runGateActionKey(String gateId) => 'gate:$gateId';

/// Busy key of a control action, a task retry or a cancellation retry.
String runControlActionKey(RunControlAction action) => 'control:${action.name}';
String runTaskRetryKey(String taskId) => 'retryTask:$taskId';
String runIntegrationRetryKey(String taskId) => 'retryIntegration:$taskId';
const String runCancellationRetryKey = 'retryCancellation';

/// Mutations of one run. Each user action gets its own `requestId`, so the
/// runtime replays a receipt instead of acting twice when a reply is lost,
/// and carries what the user saw (`expectedSequence`,
/// `expectedEvidenceDigest`), so a decision on stale state is refused.
@riverpod
class MobileRunActions extends _$MobileRunActions {
  static const Uuid _uuid = Uuid();

  @override
  MobileRunActionState build(String hostId, String runId) =>
      const MobileRunActionState();

  Future<RunGateResolution?> resolveGate(
    RunGate gate,
    String decision, {
    String? reason,
  }) async {
    if (RunGate.requiresReason(decision) && (reason?.trim() ?? '').isEmpty) {
      throw StateError('Add a note explaining the decision.');
    }
    return _perform(runGateActionKey(gate.id), (repository) async {
      try {
        return await repository.resolveGate(
          requestId: _uuid.v4(),
          gate: gate,
          decision: decision,
          reason: reason,
        );
      } on Object catch (error) {
        if (isStaleGateError(error)) _markStale(gate.id);
        rethrow;
      }
    });
  }

  /// The user looked at the gate again; offer its decisions once more.
  void clearStale(String gateId) {
    if (!state.staleGateIds.contains(gateId)) return;
    state = MobileRunActionState(
      busy: state.busy,
      staleGateIds: <String>{...state.staleGateIds}..remove(gateId),
    );
    ref.invalidate(mobileRunGateProvider(hostId, gateId));
    ref.invalidate(mobileRunDetailProvider(hostId, runId));
  }

  Future<void> control(
    RunControlAction action, {
    required int expectedSequence,
    String? reason,
  }) async {
    if (action == RunControlAction.replan && (reason?.trim() ?? '').isEmpty) {
      throw StateError('Add a note explaining the change.');
    }
    await _perform(runControlActionKey(action), (repository) async {
      try {
        await repository.control(
          requestId: _uuid.v4(),
          runId: runId,
          expectedSequence: expectedSequence,
          action: action,
          reason: reason,
        );
      } on Object catch (error) {
        if (isStaleRunError(error)) {
          ref.invalidate(mobileRunDetailProvider(hostId, runId));
        }
        rethrow;
      }
    });
  }

  Future<void> retryTask(String taskId) =>
      _perform(runTaskRetryKey(taskId), (repository) async {
        await repository.retryTask(
          requestId: _uuid.v4(),
          runId: runId,
          taskId: taskId,
        );
      });

  Future<void> retryIntegration(String taskId) =>
      _perform(runIntegrationRetryKey(taskId), (repository) async {
        await repository.retryIntegration(
          requestId: _uuid.v4(),
          runId: runId,
          taskId: taskId,
        );
      });

  Future<void> retryCancellation({required int expectedSequence}) =>
      _perform(runCancellationRetryKey, (repository) async {
        await repository.retryCancellation(
          requestId: _uuid.v4(),
          runId: runId,
          expectedSequence: expectedSequence,
        );
      });

  /// Runs [action] unless the same action is already in flight, in which
  /// case a second tap does nothing and yields null.
  Future<T?> _perform<T>(
    String key,
    Future<T> Function(MobileRuntimeRunRepository repository) action,
  ) async {
    if (state.isBusy(key)) return null;
    _setBusy(key, busy: true);
    try {
      final repository = await ref.read(
        mobileRunRepositoryProvider(hostId).future,
      );
      return await action(repository);
    } finally {
      if (ref.mounted) _setBusy(key, busy: false);
    }
  }

  void _setBusy(String key, {required bool busy}) {
    final next = <String>{...state.busy};
    if (busy) {
      next.add(key);
    } else {
      next.remove(key);
    }
    state = MobileRunActionState(busy: next, staleGateIds: state.staleGateIds);
  }

  void _markStale(String gateId) {
    if (!ref.mounted) return;
    state = MobileRunActionState(
      busy: state.busy,
      staleGateIds: <String>{...state.staleGateIds, gateId},
    );
  }
}
