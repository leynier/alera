import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';

/// Recovery progress of an admitted run. Additive: an older runtime omits it,
/// and the run `status` keeps its existing wire values during recovery.
enum AutomationRecoveryStatus {
  none,
  reconnecting,
  resuming,
  retryingWithContext,
  exhausted,
}

class const AutomationRecovery({
  required final AutomationRecoveryStatus status,
  final int attempt = 0,
  final int maxAttempts = 0,
  final DateTime? interruptedAt,
  final String? code,
}) {
  static const AutomationRecovery none = AutomationRecovery(
    status: AutomationRecoveryStatus.none,
  );

  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    return AutomationRecovery(
      status: switch (map['status']) {
        'reconnecting' => AutomationRecoveryStatus.reconnecting,
        'resuming' => AutomationRecoveryStatus.resuming,
        'retryingWithContext' => AutomationRecoveryStatus.retryingWithContext,
        'exhausted' => AutomationRecoveryStatus.exhausted,
        _ => AutomationRecoveryStatus.none,
      },
      attempt: automationJsonInt(map['attempt']),
      maxAttempts: automationJsonInt(map['maxAttempts']),
      interruptedAt: automationJsonDate(map['interruptedAt']),
      code: automationJsonOptionalString(map['code']),
    );
  }

  bool get isActive =>
      status != AutomationRecoveryStatus.none &&
      status != AutomationRecoveryStatus.exhausted;
}

class const AutomationRunRecord({
  required final String id,
  required final String automationId,
  required final int number,
  required final String status,
  required final String trigger,
  required final String? summary,
  required final String? error,
  required final DateTime? scheduledAt,
  required final DateTime? finishedAt,
  final JsonMap targetIdentity = const <String, Object?>{},
  final DateTime? startedAt,
  final DateTime? lastActivityAt,
  final DateTime? cancelRequestedAt,
  final DateTime? retryAfter,
  final DateTime? absoluteDeadlineAt,
  final String? workspaceId,
  final String? tabId,
  final String? sessionId,
  final bool takenOver = false,
  final bool ownedWorkspace = false,
  final bool ownerReserved = false,
  final int attemptCount = 0,
  final int? definitionRevision,
  final String? continueFromRunId,
  final String? renderedPrompt,
  final AutomationRecovery recovery = AutomationRecovery.none,
}) {
  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    final identity = automationJsonMap(map['targetIdentity']);
    return AutomationRunRecord(
      id: automationJsonString(map['id']),
      automationId: automationJsonString(map['automationId']),
      number: automationJsonInt(map['number']),
      status: automationJsonString(map['status']),
      trigger: automationJsonString(map['trigger']),
      summary: automationJsonOptionalString(map['summary']),
      error: automationJsonOptionalString(map['error']),
      scheduledAt: automationJsonDate(map['scheduledAt']),
      finishedAt: automationJsonDate(map['finishedAt']),
      targetIdentity: identity,
      startedAt: automationJsonDate(map['startedAt']),
      lastActivityAt:
          automationJsonDate(map['lastActivityAt']) ??
          automationJsonDate(map['lastHeartbeatAt']),
      cancelRequestedAt: automationJsonDate(map['cancelRequestedAt']),
      retryAfter: automationJsonDate(map['retryAfter']),
      absoluteDeadlineAt: automationJsonDate(map['absoluteDeadlineAt']),
      workspaceId:
          automationJsonOptionalString(map['workspaceId']) ??
          automationJsonOptionalString(identity['workspaceId']),
      tabId:
          automationJsonOptionalString(map['tabId']) ??
          automationJsonOptionalString(identity['tabId']),
      sessionId:
          automationJsonOptionalString(map['sessionId']) ??
          automationJsonOptionalString(identity['sessionId']),
      takenOver: map['takenOver'] == true,
      ownedWorkspace: map['ownedWorkspace'] == true,
      ownerReserved: map['ownerReserved'] == true,
      attemptCount: automationJsonInt(map['attemptCount']),
      definitionRevision: automationJsonOptionalInt(map['definitionRevision']),
      continueFromRunId: automationJsonOptionalString(map['continueFromRunId']),
      renderedPrompt: automationJsonOptionalString(map['renderedPrompt']),
      recovery: map['recovery'] is Map
          ? AutomationRecovery.fromJson(map['recovery'])
          : AutomationRecovery.none,
    );
  }

  bool get isFinal => automationFinalRunStatuses.contains(status);

  bool get isActive => !isFinal;
}

class const AutomationAttemptRecord({
  required final String id,
  required final String runId,
  required final int number,
  required final String status,
  final String? error,
  final DateTime? startedAt,
  final DateTime? finishedAt,
  final String? launchKind,
  final String? interruptionCode,
  final String? tabId,
  final String? sessionId,
}) {
  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    return AutomationAttemptRecord(
      id: automationJsonString(map['id']),
      runId: automationJsonString(map['runId']),
      number: automationJsonInt(map['number']),
      status: automationJsonString(map['status']),
      error: automationJsonOptionalString(map['error']),
      startedAt: automationJsonDate(map['startedAt']),
      finishedAt: automationJsonDate(map['finishedAt']),
      launchKind: automationJsonOptionalString(map['launchKind']),
      interruptionCode: automationJsonOptionalString(map['interruptionCode']),
      tabId: automationJsonOptionalString(map['tabId']),
      sessionId: automationJsonOptionalString(map['sessionId']),
    );
  }
}

class const AutomationLastRun({
  required final String id,
  required final String status,
  final DateTime? finishedAt,
  final String? summary,
}) {
  static AutomationLastRun? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = automationJsonMap(value);
    final id = automationJsonOptionalString(map['id']);
    if (id == null) return null;
    return AutomationLastRun(
      id: id,
      status: automationJsonString(map['status']),
      finishedAt: automationJsonDate(map['finishedAt']),
      summary: automationJsonOptionalString(map['summary']),
    );
  }
}

const Set<String> automationFinalRunStatuses = <String>{
  'success',
  'failure',
  'blocked',
  'timeout',
  'cancelled',
  'precheckSkipped',
  'misfireSkipped',
  'overlapSkipped',
  'queueLimitSkipped',
};
