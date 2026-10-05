import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';

enum AutomationDraftField {
  workspaceId,
  sourceBranch,
  projectId,
  hostId,
  tabId,
  conversationId,
  agentProfileId,
}

/// Everything the four authoring steps edit. The execution target type starts
/// unset in every entry point; context may only fill fields of the type the
/// user already chose.
class const AutomationDraft({
  final String name = '',
  final String description = '',
  final String promptTemplate = '',
  final List<String> tagIds = const <String>[],
  final AutomationSchedulePreset schedule = AutomationSchedulePreset.initial,
  final String? timezone,
  final String startAt = '',
  final String endAt = '',
  final AutomationTargetType? targetType,
  final Map<AutomationDraftField, String> targetFields =
      const <AutomationDraftField, String>{},
  final Set<AutomationDraftField> fromContext = const <AutomationDraftField>{},
  final String nameTemplate = 'auto-{{automation.slug}}-{{run.number}}',
  final String? originWorkspaceId,
  final Map<AutomationNumericField, String> numbers =
      const <AutomationNumericField, String>{},
  final String precheckCommand = '',
  final String setupPolicy = 'wait',
  final String overlapPolicy = 'skip',
  final String misfirePolicy = 'skip',
  final String cleanupPolicy = 'preserve',
  final bool notifyOnSuccess = false,
  final String? slug,
}) {
  factory fromRecord(AutomationRecord record) {
    final details = record.targetDetails;
    final fields = <AutomationDraftField, String>{
      for (final (field, key) in <(AutomationDraftField, String)>[
        (.workspaceId, 'workspaceId'),
        (.workspaceId, 'sourceWorkspaceId'),
        (.sourceBranch, 'sourceBranch'),
        (.projectId, 'projectId'),
        (.hostId, 'hostId'),
        (.tabId, 'tabId'),
        (.conversationId, 'conversationId'),
        (.agentProfileId, 'agentProfileId'),
      ])
        field: ?automationJsonOptionalString(details[key]),
    };
    final schedule = record.scheduleDetails;
    return AutomationDraft(
      name: record.name,
      description: record.description,
      promptTemplate: record.promptTemplate,
      tagIds: record.tagIds,
      schedule: AutomationSchedulePreset.fromSchedule(record.schedule),
      timezone: automationJsonOptionalString(schedule['timezone']),
      startAt: automationJsonString(schedule['startAt']),
      endAt: automationJsonString(schedule['endAt']),
      targetType: record.targetType,
      targetFields: fields,
      nameTemplate:
          automationJsonOptionalString(details['nameTemplate']) ??
          'auto-{{automation.slug}}-{{run.number}}',
      originWorkspaceId: record.originWorkspaceId,
      numbers: <AutomationNumericField, String>{
        .queueCap: '${record.queueCap}',
        .inactivityTimeoutSeconds: '${record.inactivityTimeoutSeconds}',
        .heartbeatIntervalSeconds: '${record.heartbeatIntervalSeconds}',
        .misfireGraceSeconds: '${record.misfireGraceSeconds}',
        .retryMaxAttempts: '${record.retryMaxAttempts}',
        .retryBackoffSeconds: '${record.retryBackoffSeconds}',
        .circuitFailureThreshold: '${record.circuitFailureThreshold}',
        .circuitOpenSeconds: '${record.circuitOpenSeconds}',
        .precheckTimeoutSeconds:
            '${automationJsonInt(record.precheck?['timeoutSeconds'], 120)}',
        .maxScheduledRuns:
            automationJsonOptionalString(schedule['maxScheduledRuns']) ?? '',
      },
      precheckCommand: automationJsonString(record.precheck?['command']),
      setupPolicy: record.setupPolicy,
      overlapPolicy: record.overlapPolicy,
      misfirePolicy: record.misfirePolicy,
      cleanupPolicy: record.cleanupPolicy ?? 'preserve',
      notifyOnSuccess: record.notifyOnSuccess,
      slug: record.slug,
    );
  }

  AutomationDraft copyWith({
    String? name,
    String? description,
    String? promptTemplate,
    List<String>? tagIds,
    AutomationSchedulePreset? schedule,
    String? timezone,
    String? startAt,
    String? endAt,
    AutomationTargetType? targetType,
    Map<AutomationDraftField, String>? targetFields,
    Set<AutomationDraftField>? fromContext,
    String? nameTemplate,
    Map<AutomationNumericField, String>? numbers,
    String? precheckCommand,
    String? setupPolicy,
    String? overlapPolicy,
    String? misfirePolicy,
    String? cleanupPolicy,
    bool? notifyOnSuccess,
  }) => AutomationDraft(
    name: name ?? this.name,
    description: description ?? this.description,
    promptTemplate: promptTemplate ?? this.promptTemplate,
    tagIds: tagIds ?? this.tagIds,
    schedule: schedule ?? this.schedule,
    timezone: timezone ?? this.timezone,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    targetType: targetType ?? this.targetType,
    targetFields: targetFields ?? this.targetFields,
    fromContext: fromContext ?? this.fromContext,
    nameTemplate: nameTemplate ?? this.nameTemplate,
    originWorkspaceId: originWorkspaceId,
    numbers: numbers ?? this.numbers,
    precheckCommand: precheckCommand ?? this.precheckCommand,
    setupPolicy: setupPolicy ?? this.setupPolicy,
    overlapPolicy: overlapPolicy ?? this.overlapPolicy,
    misfirePolicy: misfirePolicy ?? this.misfirePolicy,
    cleanupPolicy: cleanupPolicy ?? this.cleanupPolicy,
    notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
    slug: slug,
  );

  /// A new definition from this one: same settings and target, its own slug.
  AutomationDraft cloned() => AutomationDraft(
    name: '$effectiveName Copy',
    description: description,
    promptTemplate: promptTemplate,
    tagIds: tagIds,
    schedule: schedule,
    timezone: timezone,
    startAt: startAt,
    endAt: endAt,
    targetType: targetType,
    targetFields: targetFields,
    nameTemplate: nameTemplate,
    originWorkspaceId: originWorkspaceId,
    numbers: numbers,
    precheckCommand: precheckCommand,
    setupPolicy: setupPolicy,
    overlapPolicy: overlapPolicy,
    misfirePolicy: misfirePolicy,
    cleanupPolicy: cleanupPolicy,
    notifyOnSuccess: notifyOnSuccess,
  );

  /// Chooses a target type and drops every field of the previous one, so a
  /// value from another target type can never leak into this one.
  AutomationDraft withTargetType(AutomationTargetType type) => copyWith(
    targetType: type,
    targetFields: const <AutomationDraftField, String>{},
    fromContext: const <AutomationDraftField>{},
  );

  /// A user edit clears the "From context" mark of that field.
  AutomationDraft withTargetField(AutomationDraftField field, String? value) {
    final fields = Map<AutomationDraftField, String>.of(targetFields);
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      fields.remove(field);
    } else {
      fields[field] = trimmed;
    }
    return copyWith(
      targetFields: fields,
      fromContext: Set<AutomationDraftField>.of(fromContext)..remove(field),
    );
  }

  String? field(AutomationDraftField field) => targetFields[field];

  String number(AutomationNumericField field) =>
      numbers[field] ??
      (field == AutomationNumericField.maxScheduledRuns
          ? ''
          : '${field.defaultValue}');

  List<AutomationDraftField> get requiredTargetFields => switch (targetType) {
    null => const <AutomationDraftField>[],
    AutomationTargetType.freshTab => const [.workspaceId, .agentProfileId],
    AutomationTargetType.managedWorkspace => const [
      .workspaceId,
      .sourceBranch,
      .agentProfileId,
    ],
    AutomationTargetType.projectWorktree => const [
      .projectId,
      .sourceBranch,
      .agentProfileId,
    ],
    AutomationTargetType.projectCheckout => const [
      .projectId,
      .hostId,
      .agentProfileId,
    ],
    AutomationTargetType.existingTab => const [
      .workspaceId,
      .tabId,
      .conversationId,
    ],
  };

  String? get whatError => promptTemplate.trim().isEmpty
      ? 'Describe what the agent should do.'
      : null;

  String? get whenError => schedule.localError;

  String? get whereError {
    if (targetType == null) return 'Choose where the automation runs.';
    for (final field in requiredTargetFields) {
      if ((targetFields[field] ?? '').isEmpty) {
        return 'Complete the target before continuing.';
      }
    }
    return null;
  }

  Map<AutomationNumericField, String> get numberErrors {
    final inactivity = int.tryParse(
      number(AutomationNumericField.inactivityTimeoutSeconds),
    );
    return <AutomationNumericField, String>{
      for (final field in AutomationNumericField.values)
        field: ?field.validate(
          number(field),
          inactivityTimeoutSeconds: inactivity,
        ),
    };
  }

  String get effectiveName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final firstLine = promptTemplate.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return 'Automation';
    return firstLine.length > 48
        ? '${firstLine.substring(0, 48)}...'
        : firstLine;
  }

  JsonMap? get targetJson {
    final type = targetType;
    if (type == null) return null;
    String? value(AutomationDraftField field) => targetFields[field];
    final details = switch (type) {
      AutomationTargetType.freshTab => <String, Object?>{
        'workspaceId': value(.workspaceId),
        'agentProfileId': value(.agentProfileId),
      },
      AutomationTargetType.managedWorkspace => <String, Object?>{
        'sourceWorkspaceId': value(.workspaceId),
        'sourceBranch': value(.sourceBranch),
        'nameTemplate': nameTemplate.trim(),
        'agentProfileId': value(.agentProfileId),
      },
      AutomationTargetType.projectWorktree => <String, Object?>{
        'projectId': value(.projectId),
        'sourceBranch': value(.sourceBranch),
        'nameTemplate': nameTemplate.trim(),
        'agentProfileId': value(.agentProfileId),
      },
      AutomationTargetType.projectCheckout => <String, Object?>{
        'projectId': value(.projectId),
        'hostId': value(.hostId),
        'nameTemplate': nameTemplate.trim(),
        'agentProfileId': value(.agentProfileId),
      },
      AutomationTargetType.existingTab => <String, Object?>{
        'workspaceId': value(.workspaceId),
        'tabId': value(.tabId),
        'conversationId': value(.conversationId),
      },
    };
    return <String, Object?>{
      type.key: <String, Object?>{
        for (final entry in details.entries)
          if (entry.value != null) entry.key: entry.value,
      },
    };
  }

  /// The partial definition sent to `automation.create`, `automation.patch`
  /// and `automation.readiness`. The runtime fills ids, slugs, revisions,
  /// actors and timestamps.
  JsonMap toDefinition({bool draft = false}) {
    int numeric(AutomationNumericField field) =>
        int.tryParse(number(field)) ?? field.defaultValue;
    final maxRuns = int.tryParse(
      number(AutomationNumericField.maxScheduledRuns),
    );
    final bounds = <String, Object?>{
      if (startAt.trim().isNotEmpty) 'startAt': startAt.trim(),
      if (endAt.trim().isNotEmpty) 'endAt': endAt.trim(),
      'maxScheduledRuns': ?maxRuns,
    };
    final target = targetJson;
    return <String, Object?>{
      'name': effectiveName,
      'slug': ?slug,
      'description': description.trim(),
      'promptTemplate': promptTemplate.trim(),
      'tagIds': tagIds,
      'schedule': schedule.toSchedule(timezone: timezone, bounds: bounds),
      'target': ?target,
      if (targetType == AutomationTargetType.projectCheckout ||
          targetType == AutomationTargetType.projectWorktree)
        'projectId': targetFields[AutomationDraftField.projectId],
      'originWorkspaceId': originWorkspaceId,
      'setupPolicy': setupPolicy,
      'overlapPolicy': overlapPolicy,
      'misfirePolicy': misfirePolicy,
      'cleanupPolicy': cleanupPolicy,
      'notifyOnSuccess': notifyOnSuccess,
      'precheck': precheckCommand.trim().isEmpty
          ? null
          : <String, Object?>{
              'command': precheckCommand.trim(),
              'timeoutSeconds': numeric(.precheckTimeoutSeconds),
            },
      for (final field in <AutomationNumericField>[
        .queueCap,
        .inactivityTimeoutSeconds,
        .heartbeatIntervalSeconds,
        .misfireGraceSeconds,
        .retryMaxAttempts,
        .retryBackoffSeconds,
        .circuitFailureThreshold,
        .circuitOpenSeconds,
      ])
        field.key: numeric(field),
      if (draft) 'state': 'draft',
    };
  }
}
