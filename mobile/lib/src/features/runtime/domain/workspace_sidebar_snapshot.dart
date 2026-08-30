import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

class const WorkspaceTagSummary({
  required final String id,
  required final String name,
  final String? color,
}) {
  factory fromJson(Map<String, Object?> json) {
    return WorkspaceTagSummary(
      id: json.requiredString('id'),
      name: json.requiredString('name'),
      color: json.optionalString('color'),
    );
  }
}

class const AgentPresenceSummary({
  required final String terminalSessionId,
  required final String workspaceId,
  required final String tabId,
  required final String agentType,
  required final String state,
  final DateTime? stateStartedAt,
  final DateTime? updatedAt,
  final String prompt = '',
  final String? toolName,
  final String? toolInput,
  final String? lastAssistantMessage,
  final bool? interrupted,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentPresenceSummary(
      terminalSessionId: json.requiredString('handle'),
      workspaceId: json.requiredString('workspaceId'),
      tabId: json.requiredString('tabId'),
      agentType: json.optionalString('agentType') ?? 'unknown',
      state: json.optionalString('agentState') ?? 'done',
      stateStartedAt: DateTime.tryParse(
        json.optionalString('stateStartedAt') ?? '',
      )?.toUtc(),
      updatedAt: DateTime.tryParse(json.optionalString('updatedAt') ?? '')
          ?.toUtc(),
      prompt: json.optionalString('prompt') ?? '',
      toolName: json.optionalString('toolName'),
      toolInput: json.optionalString('toolInput'),
      lastAssistantMessage: json.optionalString('lastAssistantMessage'),
      interrupted: json['interrupted'] as bool?,
    );
  }
}

class const WorkspaceSidebarSnapshot({
  required final List<ProjectSummary> projects,
  required final List<WorkspaceSummary> workspaces,
  required final List<WorkspaceTagSummary> tags,
  required final Map<String, DateTime> activity,
  required final MobileViewPrefs viewPrefs,
  required final bool confirmWorkspaceRemoval,
  final String? defaultAgentProfileId,
  final List<AgentPresenceSummary> agentPresence =
      const <AgentPresenceSummary>[],
  final Map<String, int> terminalTabCountByWorkspaceId = const <String, int>{},
}) {
  factory fromJson(Map<String, Object?> json) {
    final activity = <String, DateTime>{};
    for (final entry in json.mapValue('activity').entries) {
      final value = entry.value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          activity[entry.key] = parsed;
        }
      }
    }
    return WorkspaceSidebarSnapshot(
      projects: <ProjectSummary>[
        for (final item in json.objectList('projects'))
          ProjectSummary.fromJson(asJsonMap(item)),
      ],
      workspaces: <WorkspaceSummary>[
        for (final item in json.objectList('workspaces'))
          WorkspaceSummary.fromJson(asJsonMap(item)),
      ],
      tags: <WorkspaceTagSummary>[
        for (final item in json.objectList('tags'))
          WorkspaceTagSummary.fromJson(asJsonMap(item)),
      ],
      activity: activity,
      viewPrefs: .fromRecordJson(json.mapValue('viewPrefs')),
      confirmWorkspaceRemoval:
          json.mapValue('runtimeSettings')['confirmWorkspaceRemoval'] != false,
      defaultAgentProfileId: json
          .mapValue('runtimeSettings')
          .optionalString('defaultAgentProfileId'),
      agentPresence: <AgentPresenceSummary>[
        for (final item in json.objectList('agentPresence'))
          AgentPresenceSummary.fromJson(asJsonMap(item)),
      ],
      terminalTabCountByWorkspaceId: <String, int>{
        for (final entry
            in json.mapValue('terminalTabCountByWorkspaceId').entries)
          if (entry.value is num) entry.key: (entry.value as num).toInt(),
      },
    );
  }
}
