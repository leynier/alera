import 'package:alera_automations/src/automation_draft.dart';
import 'package:alera_automations/src/automation_json_fields.dart';
import 'package:alera_automations/src/automation_models.dart';

/// Agent chat runtime modes, least to most access, as the runtime spells
/// them (`AGENT_CHAT_RUNTIME_MODES`).
const List<String> automationAgentChatRuntimeModes = <String>[
  'approval-required',
  'auto-accept-edits',
  'auto',
  'full-access',
];

/// The ceiling a new agent chat target starts with: the most access a chat
/// can be given. A person may lower it.
const String automationDefaultRuntimeModeCeiling = 'full-access';

/// The most permissive of [modes] (runtime mode wire names) the runtime
/// knows, or null when it knows none of them.
String? automationMostPermissiveMode(Iterable<String> modes) {
  String? best;
  var bestRank = -1;
  for (final mode in modes) {
    final rank = automationAgentChatRuntimeModes.indexOf(mode);
    if (rank > bestRank) {
      best = mode;
      bestRank = rank;
    }
  }
  return best;
}

/// The fields of an `agentChat` target (`automationAgentChatTargetV1`).
/// With [chatId] every run posts into that chat; without it each run starts
/// a new chat in [workspaceId] with [provider], [providerInstanceId],
/// [model] and [reasoningEffort].
final class const AutomationAgentChatTarget({
  final String? chatId,
  final String? workspaceId,
  final String? runtimeModeCeiling,
  final String? provider,
  final String? providerInstanceId,
  final String? model,
  final String? reasoningEffort,
}) {
  factory fromJson(JsonMap json) {
    String? text(String key) => automationJsonOptionalString(json[key]);
    return AutomationAgentChatTarget(
      chatId: text('chatId'),
      workspaceId: text('workspaceId'),
      runtimeModeCeiling: text('runtimeModeCeiling'),
      provider: text('provider'),
      providerInstanceId: text('providerInstanceId'),
      model: text('model'),
      reasoningEffort: text('reasoningEffort'),
    );
  }

  /// Every run starts its own chat rather than posting into [chatId].
  bool get newChatEachRun => chatId == null;

  /// Whether the runtime would accept it: a workspace, then a chat or an
  /// agent to start one with.
  bool get isComplete =>
      workspaceId != null && (chatId != null || provider != null);

  /// The fields the runtime reads, empty ones left out. A new chat keeps no
  /// chat id and a bound chat keeps no agent, so a switch between them never
  /// sends both.
  JsonMap toJson() => <String, Object?>{
    'chatId': ?chatId,
    'workspaceId': ?workspaceId,
    'runtimeModeCeiling': ?runtimeModeCeiling,
    if (newChatEachRun) ...<String, Object?>{
      'provider': ?provider,
      'providerInstanceId': ?providerInstanceId,
      'model': ?model,
      'reasoningEffort': ?reasoningEffort,
    },
  };

  /// Posts every run into [chatId] of [workspaceId].
  AutomationAgentChatTarget boundTo(String chatId) => AutomationAgentChatTarget(
    chatId: chatId,
    workspaceId: workspaceId,
    runtimeModeCeiling: runtimeModeCeiling,
  );

  /// Starts a new chat for each run, keeping the agent chosen before.
  AutomationAgentChatTarget newChat() => AutomationAgentChatTarget(
    workspaceId: workspaceId,
    runtimeModeCeiling: runtimeModeCeiling,
    provider: provider,
    providerInstanceId: providerInstanceId,
    model: model,
    reasoningEffort: reasoningEffort,
  );

  /// The agent and model each new chat starts with. A model change drops an
  /// effort the person chose for the previous one.
  AutomationAgentChatTarget withAgent({
    required String provider,
    required String providerInstanceId,
    String? model,
    String? reasoningEffort,
  }) => AutomationAgentChatTarget(
    workspaceId: workspaceId,
    runtimeModeCeiling: runtimeModeCeiling,
    provider: provider,
    providerInstanceId: providerInstanceId,
    model: model,
    reasoningEffort: reasoningEffort,
  );

  /// [withAgent] for an agent picked from the catalog, whose runtime modes
  /// are [modes]. A ceiling the agent offers stays; otherwise it becomes the
  /// most access the agent offers.
  AutomationAgentChatTarget pickAgent({
    required String provider,
    required String providerInstanceId,
    String? model,
    Iterable<String> modes = const <String>[],
  }) {
    final next = withAgent(
      provider: provider,
      providerInstanceId: providerInstanceId,
      model: model,
    );
    final offered = modes.toSet();
    final ceiling = runtimeModeCeiling;
    if (ceiling != null && (offered.isEmpty || offered.contains(ceiling))) {
      return next;
    }
    return next.withRuntimeModeCeiling(
      automationMostPermissiveMode(offered) ??
          automationDefaultRuntimeModeCeiling,
    );
  }

  AutomationAgentChatTarget withReasoningEffort(String? effort) =>
      AutomationAgentChatTarget(
        chatId: chatId,
        workspaceId: workspaceId,
        runtimeModeCeiling: runtimeModeCeiling,
        provider: provider,
        providerInstanceId: providerInstanceId,
        model: model,
        reasoningEffort: effort,
      );

  AutomationAgentChatTarget withRuntimeModeCeiling(String? mode) =>
      AutomationAgentChatTarget(
        chatId: chatId,
        workspaceId: workspaceId,
        runtimeModeCeiling: mode,
        provider: provider,
        providerInstanceId: providerInstanceId,
        model: model,
        reasoningEffort: reasoningEffort,
      );
}

/// Reading and editing the agent chat target of a draft.
extension AutomationAgentChatDraft on AutomationDraft {
  AutomationAgentChatTarget get agentChat =>
      AutomationAgentChatTarget.fromJson(agentChatTarget);

  /// Replaces the agent chat target's fields, keeping stored fields this
  /// client does not know.
  AutomationDraft withAgentChat(AutomationAgentChatTarget target) {
    const known = <String>{
      'chatId',
      'workspaceId',
      'runtimeModeCeiling',
      'provider',
      'providerInstanceId',
      'model',
      'reasoningEffort',
    };
    return copyWith(
      targetType: AutomationTargetType.agentChat,
      agentChatTarget: <String, Object?>{
        for (final entry in agentChatTarget.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
        ...target.toJson(),
      },
    );
  }

  /// Chooses [workspaceId] for the agent chat. A chat of another workspace
  /// cannot be kept; the agent can.
  AutomationDraft withAgentChatWorkspace(String workspaceId) {
    final current = agentChat;
    if (current.workspaceId == workspaceId) return this;
    return withAgentChat(
      AutomationAgentChatTarget(
        workspaceId: workspaceId,
        runtimeModeCeiling:
            current.runtimeModeCeiling ?? automationDefaultRuntimeModeCeiling,
        provider: current.provider,
        providerInstanceId: current.providerInstanceId,
        model: current.model,
        reasoningEffort: current.reasoningEffort,
      ),
    );
  }
}
