import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_selection.dart';

class const AgentChatModelPreferences({
  final List<String> hidden = const <String>[],
  final List<String> order = const <String>[],
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatModelPreferences(
      hidden: List.unmodifiableOf(agentChatJsonStringList(json['hidden'])),
      order: List.unmodifiableOf(agentChatJsonStringList(json['order'])),
    );
  }

  AgentChatJson toJson() => <String, Object?>{'hidden': hidden, 'order': order};
}

class const AgentChatPreferences({
  final AgentChatSelection? rememberedSelection,
  final AgentChatSelection? defaultSelection,
  final Map<String, AgentChatSelection> projectDefaults =
      const <String, AgentChatSelection>{},
  final Map<String, AgentChatModelPreferences> models =
      const <String, AgentChatModelPreferences>{},
  final List<AgentChatSelection> favorites = const <AgentChatSelection>[],
  final int revision = 0,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatPreferences(
      rememberedSelection: _selection(json['rememberedSelection']),
      defaultSelection: _selection(json['defaultSelection']),
      projectDefaults: Map.unmodifiableOf(<String, AgentChatSelection>{
        for (final entry in agentChatJsonMap(json['projectDefaults']).entries)
          if (_selection(entry.value) case final selection?)
            entry.key: selection,
      }),
      models: Map.unmodifiableOf(<String, AgentChatModelPreferences>{
        for (final entry in agentChatJsonMap(json['models']).entries)
          if (entry.value is Map)
            entry.key: AgentChatModelPreferences.fromJson(entry.value),
      }),
      favorites: List.unmodifiableOf(<AgentChatSelection>[
        for (final entry in agentChatJsonList(json['favorites']))
          ?_selection(entry),
      ]),
      revision: agentChatJsonInt(json['revision']) ?? 0,
    );
  }

  AgentChatSelection? resolve({
    required List<AgentChatProviderInstance> providers,
    String? projectId,
    AgentChatSelection? launchingSelection,
    String? workspaceId,
    String? launchingWorkspaceId,
  }) => resolveAgentChatSelection(
    providers: providers,
    projectDefault: projectDefaults[projectId],
    launchingSelection:
        workspaceId != null && workspaceId == launchingWorkspaceId
        ? launchingSelection
        : null,
    defaultSelection: defaultSelection,
    rememberedSelection: rememberedSelection,
  );
}

AgentChatSelection? _selection(Object? value) {
  if (value is! Map || agentChatJsonString(value['providerInstanceId']) == null)
    return null;
  return AgentChatSelection.fromJson(value);
}
