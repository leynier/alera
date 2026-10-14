import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_wire.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';

/// Whether a provider's chats get the orchestration tools, so the agent can
/// delegate further. A chat without them still runs a task it is given.
class const AgentChatOrchestrationSupport({
  required final bool supported,
  final String? reason,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatOrchestrationSupport(
      supported: agentChatJsonBool(json['supported']),
      reason: agentChatJsonString(json['reason']),
    );
  }
}

/// `chatOrchestration.capabilities`: the provider catalog, the runtime modes
/// a task may use and the longest wait.
class const AgentChatOrchestrationCapabilities({
  required final List<AgentChatProviderInstance> providers,
  final Map<String, AgentChatOrchestrationSupport> orchestration =
      const <String, AgentChatOrchestrationSupport>{},
  final List<AgentChatRuntimeMode> ceilingRuntimeModes =
      const <AgentChatRuntimeMode>[],
  final int maxWaitSeconds = AgentChatOrchestrationWire.maxWaitSeconds,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final rows = agentChatJsonList(json['providers']);
    return AgentChatOrchestrationCapabilities(
      providers: agentChatProvidersFromJson(rows),
      orchestration: <String, AgentChatOrchestrationSupport>{
        for (final row in rows)
          if (agentChatJsonString(
                agentChatJsonMap(row)['providerInstanceId'] ??
                    agentChatJsonMap(row)['id'],
              )
              case final id?)
            id: AgentChatOrchestrationSupport.fromJson(
              agentChatJsonMap(row)['orchestration'],
            ),
      },
      ceilingRuntimeModes: AgentChatRuntimeMode.listFromJson(
        json['ceilingRuntimeModes'] ?? json['runtimeModes'],
      ),
      maxWaitSeconds:
          agentChatJsonInt(json['maxWaitSeconds']) ??
          AgentChatOrchestrationWire.maxWaitSeconds,
    );
  }

  /// The same flags over another catalog, such as the providers of the
  /// workspace's own host.
  AgentChatOrchestrationCapabilities withProviders(
    List<AgentChatProviderInstance> providers,
  ) => AgentChatOrchestrationCapabilities(
    providers: providers,
    orchestration: orchestration,
    ceilingRuntimeModes: ceilingRuntimeModes,
    maxWaitSeconds: maxWaitSeconds,
  );

  AgentChatOrchestrationSupport? supportFor(String providerInstanceId) =>
      orchestration[providerInstanceId];
}

/// A chat as `chatOrchestration.list` and `read` describe it: the agent chat
/// summary plus where it lives, across projects and hosts.
class const AgentChatDirectoryEntry({
  required final AgentChatSummary chat,
  final String? projectId,
  final String? hostId,
  final String? projectName,
  final String? workspaceName,
  final String? parentChatId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final lineage = agentChatJsonMap(json['lineage']);
    return AgentChatDirectoryEntry(
      chat: AgentChatSummary.fromJson(json),
      projectId: agentChatJsonString(json['projectId']),
      hostId: agentChatJsonString(json['hostId']),
      projectName: agentChatJsonString(json['projectName']),
      workspaceName: agentChatJsonString(json['workspaceName']),
      parentChatId: agentChatJsonString(lineage['parentChatId']),
    );
  }

  String get chatId => chat.chatId;

  String get workspaceId => chat.workspaceId;

  String get title => chat.title.trim().isEmpty ? 'Untitled Chat' : chat.title;
}

List<AgentChatDirectoryEntry> agentChatDirectoryFromJson(Object? value) =>
    <AgentChatDirectoryEntry>[
      for (final row in agentChatJsonList(agentChatJsonMap(value)['chats']))
        if (row is Map && agentChatJsonString(row['chatId']) != null)
          AgentChatDirectoryEntry.fromJson(row),
    ];

enum AgentChatTranscriptRole { user, assistant }

/// User and assistant text only: `read` never returns reasoning, tool
/// payloads or provider data.
class const AgentChatTranscriptMessage({
  required final String itemId,
  required final AgentChatTranscriptRole role,
  required final String text,
  required final DateTime createdAt,
  final AgentChatItemOrigin? origin,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTranscriptMessage(
      itemId: agentChatJsonText(json['itemId']),
      role: agentChatWireToken(json['role']) == 'assistant'
          ? AgentChatTranscriptRole.assistant
          : AgentChatTranscriptRole.user,
      text: agentChatJsonText(json['text']),
      createdAt:
          agentChatJsonDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      origin: json['origin'] is Map
          ? AgentChatItemOrigin.fromJson(json['origin'])
          : null,
    );
  }
}

class const AgentChatTranscriptPlan({
  required final String itemId,
  final String? explanation,
  final List<AgentChatPlanStep> steps = const <AgentChatPlanStep>[],
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTranscriptPlan(
      itemId: agentChatJsonText(json['itemId']),
      explanation: agentChatJsonString(json['explanation']),
      steps: <AgentChatPlanStep>[
        for (final step in agentChatJsonList(json['steps']))
          AgentChatPlanStep.fromJson(step),
      ],
    );
  }
}

/// `chatOrchestration.read`: a bounded view of a chat's conversation.
class const AgentChatTranscript({
  required final AgentChatDirectoryEntry chat,
  final List<AgentChatTranscriptMessage> messages =
      const <AgentChatTranscriptMessage>[],
  final List<AgentChatTranscriptPlan> plans = const <AgentChatTranscriptPlan>[],
  final bool truncated = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTranscript(
      chat: AgentChatDirectoryEntry.fromJson(json['chat']),
      messages: <AgentChatTranscriptMessage>[
        for (final message in agentChatJsonList(json['messages']))
          AgentChatTranscriptMessage.fromJson(message),
      ],
      plans: <AgentChatTranscriptPlan>[
        for (final plan in agentChatJsonList(json['plans']))
          AgentChatTranscriptPlan.fromJson(plan),
      ],
      truncated: agentChatJsonBool(json['truncated']),
    );
  }
}
