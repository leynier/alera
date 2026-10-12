import 'dart:convert';

import 'package:alera_automations/src/automation_field_bounds.dart';
import 'package:alera_automations/src/automation_json_fields.dart';
import 'package:alera_automations/src/automation_models.dart';
import 'package:alera_automations/src/automation_reuse_policy.dart';
import 'package:alera_automations/src/automation_schedule_preset.dart';

enum AutomationDraftField {
  workspaceId,
  parentWorkspaceId,
  sourceBranch,
  projectId,
  hostId,
  tabId,
  conversationId,
  agentProfileId,
  workspaceSectionId,
}

/// Everything the four authoring steps edit. The execution target type starts
/// unset in every entry point; context may only fill fields of the type the
/// user already chose.
class const AutomationDraft({
  final String name = '',
  final String description = '',
  final String promptTemplate = '',
  final AutomationSchedulePreset schedule = AutomationSchedulePreset.initial,
  final String? timezone,
  final String startAt = '',
  final String endAt = '',
  final AutomationTargetType? targetType,
  final AutomationWorktreeSource worktreeSource =
      AutomationWorktreeSource.project,
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
  final List<String> workspaceTagIds = const <String>[],
  final AutomationReusePolicy reusePolicy = AutomationReusePolicy.newEachRun,
}) {
  factory fromRecord(AutomationRecord record) {
    final details = record.targetDetails;
    final placement = automationJsonMap(record.raw['workspacePlacement']);
    final fields = <AutomationDraftField, String>{
      for (final (field, key) in <(AutomationDraftField, String)>[
        (.workspaceId, 'workspaceId'),
        (.parentWorkspaceId, 'sourceWorkspaceId'),
        (.parentWorkspaceId, 'parentWorkspaceId'),
        (.sourceBranch, 'sourceBranch'),
        (.projectId, 'projectId'),
        (.hostId, 'hostId'),
        (.tabId, 'tabId'),
        (.conversationId, 'conversationId'),
        (.agentProfileId, 'agentProfileId'),
      ])
        field: ?automationJsonOptionalString(details[key]),
      .workspaceSectionId: ?automationJsonOptionalString(
        placement['sectionId'],
      ),
    };
    final schedule = record.scheduleDetails;
    return AutomationDraft(
      name: record.name,
      description: record.description,
      promptTemplate: record.promptTemplate,
      schedule: AutomationSchedulePreset.fromSchedule(record.schedule),
      timezone: automationJsonOptionalString(schedule['timezone']),
      startAt: automationJsonString(schedule['startAt']),
      endAt: automationJsonString(schedule['endAt']),
      targetType: record.targetType,
      worktreeSource: record.worktreeSource ?? AutomationWorktreeSource.project,
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
      workspaceTagIds: automationJsonStringList(placement['tagIds']),
      reusePolicy: record.reusePolicy,
    );
  }

  AutomationDraft copyWith({
    String? name,
    String? description,
    String? promptTemplate,
    AutomationSchedulePreset? schedule,
    String? timezone,
    String? startAt,
    String? endAt,
    AutomationTargetType? targetType,
    AutomationWorktreeSource? worktreeSource,
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
    List<String>? workspaceTagIds,
    AutomationReusePolicy? reusePolicy,
  }) => AutomationDraft(
    name: name ?? this.name,
    description: description ?? this.description,
    promptTemplate: promptTemplate ?? this.promptTemplate,
    schedule: schedule ?? this.schedule,
    timezone: timezone ?? this.timezone,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    targetType: targetType ?? this.targetType,
    worktreeSource: worktreeSource ?? this.worktreeSource,
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
    workspaceTagIds: workspaceTagIds ?? this.workspaceTagIds,
    reusePolicy: reusePolicy ?? this.reusePolicy,
  );

  /// A new definition from this one: same settings and target, its own slug.
  AutomationDraft cloned() => AutomationDraft(
    name: '$effectiveName Copy',
    description: description,
    promptTemplate: promptTemplate,
    schedule: schedule,
    timezone: timezone,
    startAt: startAt,
    endAt: endAt,
    targetType: targetType,
    worktreeSource: worktreeSource,
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
    workspaceTagIds: workspaceTagIds,
    reusePolicy: reusePolicy,
  );

  /// Whether this draft edits a stored definition rather than creating one.
  bool get editsExisting => slug != null;

  /// Chooses a target type and drops every field of the previous one, so a
  /// value from another target type can never leak into this one.
  ///
  /// The reuse policy is kept when it still applies to [type]; otherwise it
  /// falls back to the first one that does.
  AutomationDraft withTargetType(
    AutomationTargetType type, {
    AutomationWorktreeSource worktreeSource = AutomationWorktreeSource.project,
  }) {
    final policies = applicableReusePolicies(type);
    return copyWith(
      targetType: type,
      worktreeSource: worktreeSource,
      targetFields: <AutomationDraftField, String>{
        if (type.createsWorkspace) .workspaceSectionId: ?workspaceSectionId,
      },
      fromContext: const <AutomationDraftField>{},
      reusePolicy: policies.contains(reusePolicy)
          ? reusePolicy
          : policies.first,
    );
  }

  String? get workspaceSectionId =>
      targetFields[AutomationDraftField.workspaceSectionId];

  /// Tags and section of the workspaces the runs create. Always sent, empty
  /// when the target creates none, so an edit that changes the target clears
  /// a placement the new target cannot use.
  JsonMap get workspacePlacement => targetType?.createsWorkspace == true
      ? <String, Object?>{
          'tagIds': workspaceTagIds,
          'sectionId': ?workspaceSectionId,
        }
      : const <String, Object?>{};

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
    AutomationTargetType.worktree => switch (worktreeSource) {
      AutomationWorktreeSource.workspace => const [
        .parentWorkspaceId,
        .sourceBranch,
        .agentProfileId,
      ],
      AutomationWorktreeSource.project => const [
        .projectId,
        .sourceBranch,
        .agentProfileId,
      ],
    },
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

  /// Problems in the fields the user can edit. Hidden fields keep their
  /// stored values, but the inactivity timeout still may not drop below the
  /// heartbeat interval the runtime pairs it with.
  Map<AutomationNumericField, String> get numberErrors {
    final heartbeat = int.tryParse(
      number(AutomationNumericField.heartbeatIntervalSeconds),
    );
    return <AutomationNumericField, String>{
      for (final field in AutomationNumericField.editableFields)
        field: ?field.validate(
          number(field),
          heartbeatIntervalSeconds: heartbeat,
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
      AutomationTargetType.worktree => <String, Object?>{
        if (worktreeSource == AutomationWorktreeSource.workspace)
          'parentWorkspaceId': value(.parentWorkspaceId)
        else
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
  /// actors, timestamps and the bound target.
  ///
  /// `reusePolicy` is sent only to a runtime that advertises
  /// [automationReuseCapability]. A new definition omits the default, but an
  /// edit always sends it: `automation.patch` merges, so an omitted policy
  /// would keep a stored reuse the user just turned off.
  JsonMap toDefinition({bool draft = false, bool supportsReuse = false}) {
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
      'schedule': schedule.toSchedule(timezone: timezone, bounds: bounds),
      'target': ?target,
      if (targetType == AutomationTargetType.projectCheckout ||
          (targetType == AutomationTargetType.worktree &&
              worktreeSource == AutomationWorktreeSource.project))
        'projectId': targetFields[AutomationDraftField.projectId],
      'originWorkspaceId': originWorkspaceId,
      'setupPolicy': setupPolicy,
      'overlapPolicy': overlapPolicy,
      'misfirePolicy': misfirePolicy,
      'cleanupPolicy': cleanupPolicy,
      'notifyOnSuccess': notifyOnSuccess,
      'workspacePlacement': workspacePlacement,
      if (supportsReuse && (reusePolicy.reuses || editsExisting))
        'reusePolicy': reusePolicy.wireValue,
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

  /// A stable fingerprint of what saving would send, so an editor can tell
  /// whether the user changed anything. Context marks are not part of it.
  String get definitionKey => jsonEncode(toDefinition(supportsReuse: true));
}
