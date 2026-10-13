import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// How much a session may do without asking; the runtime translates it into
/// each provider's own approval and sandbox policy.
enum AgentChatRuntimeMode(this.wire) {
  approvalRequired('approval-required'),
  autoAcceptEdits('auto-accept-edits'),
  auto('auto'),
  fullAccess('full-access');

  final String wire;

  static AgentChatRuntimeMode? tryParse(Object? value) {
    final token = agentChatWireToken(value);
    for (final mode in values) {
      if (agentChatWireToken(mode.wire) == token) return mode;
    }
    return null;
  }

  static List<AgentChatRuntimeMode> listFromJson(Object? value) =>
      <AgentChatRuntimeMode>[
        for (final item in agentChatJsonList(value))
          ?AgentChatRuntimeMode.tryParse(item),
      ];
}

enum AgentChatInteractionMode(this.wire) {
  standard('default'),
  plan('plan');

  final String wire;

  static AgentChatInteractionMode? tryParse(Object? value) =>
      switch (agentChatWireToken(value)) {
        'default' => AgentChatInteractionMode.standard,
        'plan' => AgentChatInteractionMode.plan,
        _ => null,
      };

  static List<AgentChatInteractionMode> listFromJson(Object? value) =>
      <AgentChatInteractionMode>[
        for (final item in agentChatJsonList(value))
          ?AgentChatInteractionMode.tryParse(item),
      ];
}

enum AgentChatSessionStatus {
  starting,
  ready,
  running,
  waiting,
  stopped,
  archived,
  error;

  static AgentChatSessionStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatSessionStatus.values,
    AgentChatSessionStatus.stopped,
  );

  /// Whether the provider process is expected to accept a new turn.
  bool get acceptsTurns =>
      this == AgentChatSessionStatus.ready ||
      this == AgentChatSessionStatus.running ||
      this == AgentChatSessionStatus.waiting;
}

enum AgentChatTurnStatus {
  running,
  completed,
  failed,
  interrupted,
  cancelled;

  static AgentChatTurnStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatTurnStatus.values,
    AgentChatTurnStatus.completed,
  );

  bool get isTerminal => this != AgentChatTurnStatus.running;
}

enum AgentChatRequestKind {
  commandExecutionApproval,
  fileReadApproval,
  fileChangeApproval,
  applyPatchApproval,
  execCommandApproval,
  mcpElicitationApproval,
  permissionApproval,
  toolUserInput,
  dynamicToolCall,
  authTokensRefresh,
  unknown;

  static AgentChatRequestKind fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatRequestKind.values,
    AgentChatRequestKind.unknown,
  );

  bool get isApproval => switch (this) {
    AgentChatRequestKind.commandExecutionApproval ||
    AgentChatRequestKind.fileReadApproval ||
    AgentChatRequestKind.fileChangeApproval ||
    AgentChatRequestKind.applyPatchApproval ||
    AgentChatRequestKind.execCommandApproval ||
    AgentChatRequestKind.permissionApproval => true,
    _ => false,
  };

  bool get isUserInput => this == AgentChatRequestKind.toolUserInput;

  bool get isElicitation => this == AgentChatRequestKind.mcpElicitationApproval;
}

enum AgentChatApprovalDecision(this.wire) {
  accept('accept'),
  acceptForSession('acceptForSession'),
  acceptAlways('acceptAlways'),
  decline('decline'),
  cancel('cancel');

  final String wire;

  static AgentChatApprovalDecision? tryParse(Object? value) {
    final token = agentChatWireToken(value);
    for (final decision in values) {
      if (agentChatWireToken(decision.wire) == token) return decision;
    }
    return null;
  }

  bool get accepts =>
      this == AgentChatApprovalDecision.accept ||
      this == AgentChatApprovalDecision.acceptForSession ||
      this == AgentChatApprovalDecision.acceptAlways;
}

enum AgentChatElicitationAction(this.wire) {
  accept('accept'),
  decline('decline'),
  cancel('cancel');

  final String wire;
}

/// Whether a send starts a turn, steers the running one, or waits behind it.
enum AgentChatDelivery(this.wire) {
  auto('auto'),
  steer('steer'),
  queue('queue');

  final String wire;
}

/// How a stopped session comes back: resume the provider's own thread, or
/// start a fresh provider thread that keeps this chat's history.
enum AgentChatRecoverMode(this.wire) {
  resume('resume'),
  restart('restart');

  final String wire;
}
