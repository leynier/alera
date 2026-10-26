import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
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

  /// Workspace tab title. Additive: an older host omits it.
  final String title = '',

  /// Set when the row is an agent chat rather than a terminal agent; the
  /// phone builds these from `agentChat.list`, never from the snapshot.
  final String? chatId,

  /// The chat that delegated work to this one, when both are listed.
  final String? parentChatId,

  /// How many delegations deep this chat sits under a listed chat.
  final int depth = 0,
}) {
  bool get isChat => chatId != null;

  AgentPresenceSummary atDepth(int depth) => depth == this.depth
      ? this
      : AgentPresenceSummary(
          terminalSessionId: terminalSessionId,
          workspaceId: workspaceId,
          tabId: tabId,
          agentType: agentType,
          state: state,
          stateStartedAt: stateStartedAt,
          updatedAt: updatedAt,
          prompt: prompt,
          toolName: toolName,
          toolInput: toolInput,
          lastAssistantMessage: lastAssistantMessage,
          interrupted: interrupted,
          title: title,
          chatId: chatId,
          parentChatId: parentChatId,
          depth: depth,
        );

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
      title: json.optionalString('title') ?? '',
    );
  }
}

class const WorkspaceSidebarSnapshot({
  final List<WorkspaceSectionSummary> sections = const [],
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

  /// Main-panel terminal tab ids, keyed by workspace. Additive: an older
  /// host omits it and every agent on the row counts as main.
  final Map<String, List<String>> workspaceMainTabIds =
      const <String, List<String>>{},
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
      sections: [
        for (final item in json.objectList('sections'))
          WorkspaceSectionSummary.fromJson(asJsonMap(item)),
      ],
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
      workspaceMainTabIds: <String, List<String>>{
        for (final entry in json.mapValue('workspaceMainTabIds').entries)
          entry.key: <String>[
            if (entry.value is List)
              for (final item in entry.value as List)
                if (item is String && item.isNotEmpty) item,
          ],
      },
    );
  }
}
