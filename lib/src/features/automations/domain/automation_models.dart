import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_readiness.dart';
import 'package:alera/src/features/automations/domain/automation_run_models.dart';

export 'package:alera/src/features/automations/domain/automation_json_fields.dart'
    show JsonMap;
export 'package:alera/src/features/automations/domain/automation_readiness.dart';
export 'package:alera/src/features/automations/domain/automation_run_models.dart';

/// The execution target families. The user always picks one explicitly.
enum AutomationTargetType(final String key, final String label) {
  freshTab('freshTab', 'New Agent Tab In A Workspace'),
  projectWorktree('projectWorktree', 'New Worktree From A Project'),
  managedWorkspace('managedWorkspace', 'New Worktree From A Workspace'),
  projectCheckout('projectCheckout', 'Project Folder On A Host'),
  existingTab('existingTab', 'Continue An Agent Conversation');

  /// Whether each run creates its own workspace, which can then be given
  /// tags and a section.
  bool get createsWorkspace => switch (this) {
    managedWorkspace || projectWorktree || projectCheckout => true,
    freshTab || existingTab => false,
  };

  static AutomationTargetType? fromTarget(JsonMap target) {
    for (final type in values) {
      if (target.containsKey(type.key)) return type;
    }
    return null;
  }
}

class const AutomationRecord({
  required final String id,
  required final String slug,
  required final String name,
  required final String description,
  required final String promptTemplate,
  required final JsonMap schedule,
  required final JsonMap target,
  required final String state,
  required final int revision,
  required final DateTime? updatedAt,
  final String? projectId,
  final String? originWorkspaceId,
  final List<String> tagIds = const <String>[],
  final String setupPolicy = 'wait',
  final String? cleanupPolicy,
  final String overlapPolicy = 'skip',
  final int queueCap = 10,
  final int inactivityTimeoutSeconds = 7200,
  final int heartbeatIntervalSeconds = 60,
  final int misfireGraceSeconds = 900,
  final String misfirePolicy = 'skip',
  final int retryMaxAttempts = 3,
  final int retryBackoffSeconds = 60,
  final int circuitFailureThreshold = 3,
  final int circuitOpenSeconds = 900,
  final JsonMap? precheck,
  final bool notifyOnSuccess = false,
  final AutomationAssociation? association,
  final String? targetHostId,
  final String? targetSummary,
  final DateTime? nextRunAt,
  final AutomationLastRun? lastRun,
  final int activeRunCount = 0,
  final AutomationReadiness? readiness,
  final AutomationAttention? attention,
  final JsonMap raw = const <String, Object?>{},
}) {
  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    String text(String key, String fallback) =>
        automationJsonOptionalString(map[key]) ?? fallback;
    return AutomationRecord(
      id: automationJsonString(map['id']),
      slug: automationJsonString(map['slug']),
      name: automationJsonString(map['name']),
      description: automationJsonString(map['description']),
      promptTemplate: automationJsonString(map['promptTemplate']),
      schedule: automationJsonMap(map['schedule']),
      target: automationJsonMap(map['target']),
      state: text('state', 'draft'),
      revision: automationJsonInt(map['revision']),
      updatedAt: automationJsonDate(map['updatedAt']),
      projectId: automationJsonOptionalString(map['projectId']),
      originWorkspaceId: automationJsonOptionalString(map['originWorkspaceId']),
      tagIds: automationJsonStringList(map['tagIds']),
      setupPolicy: text('setupPolicy', 'wait'),
      cleanupPolicy: automationJsonOptionalString(map['cleanupPolicy']),
      overlapPolicy: text('overlapPolicy', 'skip'),
      queueCap: automationJsonInt(map['queueCap'], 10),
      inactivityTimeoutSeconds: automationJsonInt(
        map['inactivityTimeoutSeconds'],
        7200,
      ),
      heartbeatIntervalSeconds: automationJsonInt(
        map['heartbeatIntervalSeconds'],
        60,
      ),
      misfireGraceSeconds: automationJsonInt(map['misfireGraceSeconds'], 900),
      misfirePolicy: text('misfirePolicy', 'skip'),
      retryMaxAttempts: automationJsonInt(map['retryMaxAttempts'], 3),
      retryBackoffSeconds: automationJsonInt(map['retryBackoffSeconds'], 60),
      circuitFailureThreshold: automationJsonInt(
        map['circuitFailureThreshold'],
        3,
      ),
      circuitOpenSeconds: automationJsonInt(map['circuitOpenSeconds'], 900),
      precheck: map['precheck'] is Map
          ? automationJsonMap(map['precheck'])
          : null,
      notifyOnSuccess: map['notifyOnSuccess'] == true,
      association: AutomationAssociation.tryParse(map['association']),
      targetHostId: automationJsonOptionalString(map['targetHostId']),
      targetSummary: automationJsonOptionalString(map['targetSummary']),
      nextRunAt: automationJsonDate(map['nextRunAt']),
      lastRun: AutomationLastRun.tryParse(map['lastRun']),
      activeRunCount: automationJsonInt(map['activeRunCount']),
      readiness: map['readiness'] is Map
          ? AutomationReadiness.fromJson(map['readiness'])
          : null,
      attention: AutomationAttention.tryParse(map['attention']),
      raw: map,
    );
  }

  bool get isRecurring => schedule.containsKey('recurring');

  JsonMap get scheduleDetails => automationJsonMap(
    schedule['recurring'] ?? schedule['oneTime'] ?? schedule,
  );

  AutomationTargetType? get targetType =>
      AutomationTargetType.fromTarget(target);

  JsonMap get targetDetails {
    final type = targetType;
    return type == null
        ? const <String, Object?>{}
        : automationJsonMap(target[type.key]);
  }

  String? get agentProfileId =>
      automationJsonOptionalString(targetDetails['agentProfileId']);

  /// The workspace the target runs in or derives from, when it has one.
  String? get targetWorkspaceId =>
      automationJsonOptionalString(targetDetails['workspaceId']) ??
      automationJsonOptionalString(targetDetails['sourceWorkspaceId']);

  String? get effectiveProjectId => association?.projectId ?? projectId;

  String? get associatedWorkspaceId =>
      association?.workspaceId ?? originWorkspaceId ?? targetWorkspaceId;

  ({List<String> tagIds, String? sectionId}) get workspacePlacement {
    final placement = automationJsonMap(raw['workspacePlacement']);
    return (
      tagIds: automationJsonStringList(placement['tagIds']),
      sectionId: automationJsonOptionalString(placement['sectionId']),
    );
  }

  bool get isCompleted => state == 'archived';

  bool get isTrashed => state == 'trashed';

  bool get isEditable => !isCompleted && !isTrashed;

  bool get createdByAgent =>
      automationJsonMap(raw['createdBy'])['kind'] == 'managedAgent';

  String? get createdByLabel => automationJsonOptionalString(
    automationJsonMap(raw['createdBy'])['label'],
  );
}

class const AutomationDetail({
  required final AutomationRecord automation,
  required final List<AutomationRunRecord> runs,
  required final List<JsonMap> audit,
  required final List<JsonMap> occurrences,
  final List<AutomationAttemptRecord> attempts =
      const <AutomationAttemptRecord>[],
}) {
  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    return AutomationDetail(
      automation: .fromJson(map['automation']),
      runs: automationJsonList(map['runs'])
          .map(AutomationRunRecord.fromJson)
          .toList(growable: false),
      audit: automationJsonList(map['audit'])
          .map(automationJsonMap)
          .toList(growable: false),
      occurrences: automationJsonList(map['occurrences'])
          .map(automationJsonMap)
          .toList(growable: false),
      attempts: automationJsonList(map['attempts'])
          .map(AutomationAttemptRecord.fromJson)
          .toList(growable: false),
    );
  }

  List<AutomationAttemptRecord> attemptsFor(String runId) =>
      attempts.where((attempt) => attempt.runId == runId).toList()
        ..sort((left, right) => left.number.compareTo(right.number));
}
