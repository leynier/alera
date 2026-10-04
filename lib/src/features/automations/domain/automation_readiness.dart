import 'package:alera/src/features/automations/domain/automation_json_fields.dart';

enum AutomationIssueSeverity { error, warning }

/// One structural or execution-capability problem reported by the runtime.
///
/// Readiness never carries approval or permission switches: every issue names
/// something technical the user can fix (a prompt, schedule, target, profile,
/// CLI or host).
class const AutomationReadinessIssue({
  required final String code,
  required final String message,
  required final AutomationIssueSeverity severity,
  final String? field,
  final String? action,
}) {
  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    return AutomationReadinessIssue(
      code: automationJsonString(map['code']),
      message: automationJsonString(map['message']),
      severity: map['severity'] == 'warning'
          ? AutomationIssueSeverity.warning
          : AutomationIssueSeverity.error,
      field: automationJsonOptionalString(map['field']),
      action: automationJsonOptionalString(map['action']),
    );
  }

  bool get isError => severity == AutomationIssueSeverity.error;
}

class const AutomationReadiness({
  required final bool ready,
  final List<AutomationReadinessIssue> issues =
      const <AutomationReadinessIssue>[],
  final List<JsonMap> occurrences = const <JsonMap>[],
  final String? timezone,
}) {
  factory fromJson(Object? value) {
    final map = automationJsonMap(value);
    final issues = automationJsonList(map['issues'])
        .map(AutomationReadinessIssue.fromJson)
        .toList(growable: false);
    return AutomationReadiness(
      ready: map['ready'] is bool
          ? map['ready']! as bool
          : !issues.any((issue) => issue.isError),
      issues: issues,
      occurrences: automationJsonList(map['occurrences'])
          .map(automationJsonMap)
          .toList(growable: false),
      timezone: automationJsonOptionalString(map['timezone']),
    );
  }

  List<AutomationReadinessIssue> get errors =>
      issues.where((issue) => issue.isError).toList(growable: false);

  List<AutomationReadinessIssue> get warnings =>
      issues.where((issue) => !issue.isError).toList(growable: false);

  List<AutomationReadinessIssue> issuesFor(String field) =>
      issues.where((issue) => issue.field == field).toList(growable: false);
}

class const AutomationAttention({
  required final String code,
  required final String message,
  final DateTime? since,
}) {
  static AutomationAttention? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = automationJsonMap(value);
    final message = automationJsonOptionalString(map['message']);
    if (message == null) return null;
    return AutomationAttention(
      code: automationJsonString(map['code']),
      message: message,
      since: automationJsonDate(map['since']),
    );
  }
}

enum AutomationAssociationSource { origin, targetWorkspace, project }

/// Where a definition belongs in the sidebar. The runtime derives it from the
/// optional origin workspace first and the target workspace second; a section
/// is always the associated workspace's current section.
class const AutomationAssociation({
  required final AutomationAssociationSource source,
  final String? workspaceId,
  final String? sectionId,
  final String? projectId,
}) {
  static AutomationAssociation? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = automationJsonMap(value);
    return AutomationAssociation(
      source: switch (map['source']) {
        'origin' => AutomationAssociationSource.origin,
        'targetWorkspace' => AutomationAssociationSource.targetWorkspace,
        _ => AutomationAssociationSource.project,
      },
      workspaceId: automationJsonOptionalString(map['workspaceId']),
      sectionId: automationJsonOptionalString(map['sectionId']),
      projectId: automationJsonOptionalString(map['projectId']),
    );
  }
}
