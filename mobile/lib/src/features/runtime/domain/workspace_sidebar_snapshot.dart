import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

class WorkspaceTagSummary {
  const WorkspaceTagSummary({required this.id, required this.name, this.color});

  final String id;
  final String name;
  final String? color;

  factory WorkspaceTagSummary.fromJson(Map<String, Object?> json) {
    return WorkspaceTagSummary(
      id: json.requiredString('id'),
      name: json.requiredString('name'),
      color: json.optionalString('color'),
    );
  }
}

class AgentPresenceSummary {
  const AgentPresenceSummary({
    required this.terminalSessionId,
    required this.workspaceId,
    required this.tabId,
    required this.agentType,
    required this.state,
    this.stateStartedAt,
    this.updatedAt,
    this.prompt = '',
    this.toolName,
    this.toolInput,
    this.lastAssistantMessage,
    this.interrupted,
  });

  final String terminalSessionId;
  final String workspaceId;
  final String tabId;
  final String agentType;
  final String state;
  final DateTime? stateStartedAt;
  final DateTime? updatedAt;
  final String prompt;
  final String? toolName;
  final String? toolInput;
  final String? lastAssistantMessage;
  final bool? interrupted;

  factory AgentPresenceSummary.fromJson(Map<String, Object?> json) {
    return AgentPresenceSummary(
      terminalSessionId: json.requiredString('handle'),
      workspaceId: json.requiredString('workspaceId'),
      tabId: json.requiredString('tabId'),
      agentType: json.optionalString('agentType') ?? 'unknown',
      state: json.optionalString('agentState') ?? 'done',
      stateStartedAt: DateTime.tryParse(
        json.optionalString('stateStartedAt') ?? '',
      )?.toUtc(),
      updatedAt: DateTime.tryParse(
        json.optionalString('updatedAt') ?? '',
      )?.toUtc(),
      prompt: json.optionalString('prompt') ?? '',
      toolName: json.optionalString('toolName'),
      toolInput: json.optionalString('toolInput'),
      lastAssistantMessage: json.optionalString('lastAssistantMessage'),
      interrupted: json['interrupted'] as bool?,
    );
  }
}

class WorkspaceSidebarSnapshot {
  const WorkspaceSidebarSnapshot({
    required this.projects,
    required this.workspaces,
    required this.tags,
    required this.activity,
    required this.viewPrefs,
    required this.confirmWorkspaceRemoval,
    this.defaultAgentProfileId,
    this.agentPresence = const <AgentPresenceSummary>[],
    this.terminalTabCountByWorkspaceId = const <String, int>{},
  });

  final List<ProjectSummary> projects;
  final List<WorkspaceSummary> workspaces;
  final List<WorkspaceTagSummary> tags;
  final Map<String, DateTime> activity;
  final MobileViewPrefs viewPrefs;
  final bool confirmWorkspaceRemoval;
  final String? defaultAgentProfileId;
  final List<AgentPresenceSummary> agentPresence;
  final Map<String, int> terminalTabCountByWorkspaceId;

  factory WorkspaceSidebarSnapshot.fromJson(Map<String, Object?> json) {
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
      viewPrefs: MobileViewPrefs.fromRecordJson(json.mapValue('viewPrefs')),
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
