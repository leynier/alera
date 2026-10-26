import 'package:alera_agent_chat/src/agent_chat_goal.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_capabilities.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_command.dart';

/// What the provider behind a chat actually implements. Controls that need a
/// missing capability are hidden or disabled rather than failing on use.
class const AgentChatCapabilities({
  final bool resume = false,
  final bool interrupt = false,
  final bool approvals = false,
  final bool userInput = false,
  final bool mcpElicitation = false,
  final bool streaming = false,
  final bool modelSwitch = false,
  final bool steer = false,
  final bool fork = false,
  final bool rollback = false,
  final bool attachments = false,
  final bool images = false,
  final bool plan = false,

  /// Whether one provider-native sub-agent can be stopped on its own.
  final bool stopSubagent = false,
  final AgentChatNativeHistoryCapabilities nativeHistory =
      const AgentChatNativeHistoryCapabilities(),
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatCapabilities(
      resume: agentChatJsonBool(json['resume']),
      interrupt: agentChatJsonBool(json['interrupt']),
      approvals: agentChatJsonBool(json['approvals']),
      userInput: agentChatJsonBool(json['userInput']),
      mcpElicitation: agentChatJsonBool(json['mcpElicitation']),
      streaming: agentChatJsonBool(json['streaming']),
      modelSwitch: agentChatJsonBool(json['modelSwitch']),
      steer: agentChatJsonBool(json['steer']),
      fork: agentChatJsonBool(json['fork']),
      rollback: agentChatJsonBool(json['rollback']),
      attachments: agentChatJsonBool(json['attachments']),
      images: agentChatJsonBool(json['images']),
      plan: agentChatJsonBool(json['plan']),
      stopSubagent: agentChatJsonBool(json['stopSubagent']),
      nativeHistory: AgentChatNativeHistoryCapabilities.fromJson(
        json['nativeHistory'],
      ),
    );
  }
}

class const AgentChatSession({
  final AgentChatSessionStatus status = AgentChatSessionStatus.starting,
  final String? model,
  final String? reasoningEffort,
  final bool fileCheckpointing = false,
  final AgentChatRuntimeMode runtimeMode =
      AgentChatRuntimeMode.approvalRequired,
  final AgentChatInteractionMode interactionMode =
      AgentChatInteractionMode.standard,
  final String? activeTurnId,
  final String? cwd,
  final AgentChatCapabilities capabilities = const AgentChatCapabilities(),
  final String? errorMessage,
  final int generation = 0,

  /// The slash commands the agent advertises, for the composer's `/` menu.
  final List<AgentChatProviderCommand> commands =
      const <AgentChatProviderCommand>[],

  /// The objective the provider keeps working toward, when one is set.
  final AgentChatGoal? goal,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatSession(
      status: AgentChatSessionStatus.fromJson(json['status']),
      model: agentChatJsonString(json['model']),
      reasoningEffort: agentChatJsonString(json['reasoningEffort']),
      fileCheckpointing: agentChatJsonBool(json['fileCheckpointing']),
      runtimeMode:
          AgentChatRuntimeMode.tryParse(json['runtimeMode']) ??
          AgentChatRuntimeMode.approvalRequired,
      interactionMode:
          AgentChatInteractionMode.tryParse(json['interactionMode']) ??
          AgentChatInteractionMode.standard,
      activeTurnId: agentChatJsonString(json['activeTurnId']),
      cwd: agentChatJsonString(json['cwd']),
      capabilities: AgentChatCapabilities.fromJson(json['capabilities']),
      errorMessage: agentChatJsonString(json['errorMessage']),
      generation: agentChatJsonInt(json['generation']) ?? 0,
      commands: agentChatProviderCommandsFromJson(json['commands']),
      goal: AgentChatGoal.tryParse(json['goal']),
    );
  }

  bool get busy => activeTurnId != null;
}

class const AgentChatTurn({
  required final String id,
  required final AgentChatTurnStatus status,
  final DateTime? startedAt,
  final DateTime? completedAt,
  final String? errorMessage,
  final AgentChatFailureClass failureClass = AgentChatFailureClass.unknown,
  final String? reason,
  final String? model,
  final String? provider,
  final String? providerInstanceId,
  final int generation = 0,

  /// Who started the turn when it was not the person: `goalContinuation`
  /// for a turn the provider started on its own toward an active goal.
  final String? origin,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['turnId'] ?? json['id']);
    if (id == null) {
      throw const FormatException('Agent chat turn has no turnId.');
    }
    return AgentChatTurn(
      id: id,
      status: AgentChatTurnStatus.fromJson(json['status']),
      startedAt: agentChatJsonDate(json['startedAt']),
      completedAt: agentChatJsonDate(json['completedAt']),
      errorMessage: agentChatJsonString(json['errorMessage']),
      failureClass: AgentChatFailureClass.fromJson(json['failureClass']),
      reason: agentChatJsonString(json['reason']),
      model: agentChatJsonString(json['model']),
      provider: agentChatJsonString(json['provider']),
      providerInstanceId: agentChatJsonString(json['providerInstanceId']),
      generation: agentChatJsonInt(json['generation']) ?? 0,
      origin: agentChatJsonString(json['origin']),
    );
  }

  /// A turn the provider started by itself to keep working toward its goal,
  /// so it has no prompt of its own.
  bool get goalContinuation => origin == 'goalContinuation';

  /// A turn the runtime cut short when it restarted, rather than one the
  /// user or the provider stopped.
  bool get interruptedByRestart => reason == 'runtimeRestarted';

  Duration? get duration {
    final start = startedAt;
    final end = completedAt;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }
}

enum AgentChatUsageWindowKind {
  session,
  weekly,
  monthly,
  other;

  static AgentChatUsageWindowKind fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatUsageWindowKind.values,
    AgentChatUsageWindowKind.other,
  );
}

class const AgentChatUsageWindow({
  required final String id,
  required final AgentChatUsageWindowKind kind,
  required final String label,
  required final double usedPercent,
  final DateTime? resetsAt,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatUsageWindow(
      id: agentChatJsonText(json['id']),
      kind: AgentChatUsageWindowKind.fromJson(json['kind']),
      label: agentChatJsonText(json['label']),
      usedPercent: (agentChatJsonDouble(json['usedPercent']) ?? 0).clamp(
        0,
        100,
      ),
      resetsAt: agentChatJsonDate(json['resetsAt']),
    );
  }
}

class const AgentChatUsage({
  final int? inputTokens,
  final int? outputTokens,
  final int? cachedInputTokens,
  final int? reasoningTokens,
  final int? contextTokens,
  final int? contextWindow,
  final List<AgentChatUsageWindow> windows = const <AgentChatUsageWindow>[],
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final tokens = agentChatJsonMap(json['tokens']);
    return AgentChatUsage(
      inputTokens: agentChatJsonInt(tokens['input']),
      outputTokens: agentChatJsonInt(tokens['output']),
      cachedInputTokens: agentChatJsonInt(tokens['cached']),
      reasoningTokens: agentChatJsonInt(tokens['reasoning']),
      contextTokens: agentChatJsonInt(tokens['context']),
      contextWindow: agentChatJsonInt(tokens['contextWindow']),
      windows: <AgentChatUsageWindow>[
        for (final window in agentChatJsonList(json['windows']))
          AgentChatUsageWindow.fromJson(window),
      ],
    );
  }

  /// Share of the context window in use, when the provider reports both ends.
  double? get contextFraction {
    final used = contextTokens;
    final window = contextWindow;
    if (used == null || window == null || window <= 0) return null;
    return (used / window).clamp(0, 1).toDouble();
  }
}

enum AgentChatRecoveryKind {
  providerExited,
  resumable,
  notResumable,
  authRequired,
  providerMissing,
  unknown;

  static AgentChatRecoveryKind fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatRecoveryKind.values,
    AgentChatRecoveryKind.unknown,
  );
}

/// Present while the session cannot take turns and the runtime knows a way
/// back. The flags are what the runtime verified, not what the UI hopes.
class const AgentChatRecovery({
  required final AgentChatRecoveryKind kind,
  required final String message,
  final bool canResume = false,
  final bool canRestart = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatRecovery(
      kind: AgentChatRecoveryKind.fromJson(json['kind']),
      message:
          agentChatJsonString(json['message']) ?? 'The agent session stopped.',
      canResume: agentChatJsonBool(json['canResume']),
      canRestart: agentChatJsonBool(json['canRestart']),
    );
  }
}
