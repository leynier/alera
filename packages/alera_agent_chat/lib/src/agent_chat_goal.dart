import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_worked_actions.dart';

enum AgentChatGoalStatus {
  active,
  paused,
  blocked,
  usageLimited,
  budgetLimited,
  complete;

  /// A status this client does not know reads as paused: the goal stays
  /// visible with Resume and Clear rather than vanishing while the provider
  /// still holds it.
  static AgentChatGoalStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatGoalStatus.values,
    AgentChatGoalStatus.paused,
  );
}

/// The objective a provider (Codex `/goal`) keeps working toward across
/// turns, with what it has spent so far.
class const AgentChatGoal({
  required final String objective,
  required final AgentChatGoalStatus status,
  final int tokensUsed = 0,
  final int? tokenBudget,
  final int timeUsedSeconds = 0,
}) {
  /// The goal on the wire, or null when there is none or it has no objective.
  static AgentChatGoal? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = agentChatJsonMap(value);
    final objective = agentChatJsonString(json['objective'])?.trim();
    if (objective == null || objective.isEmpty) return null;
    return AgentChatGoal(
      objective: objective,
      status: AgentChatGoalStatus.fromJson(json['status']),
      tokensUsed: agentChatJsonInt(json['tokensUsed']) ?? 0,
      tokenBudget: agentChatJsonInt(json['tokenBudget']),
      timeUsedSeconds: agentChatJsonInt(json['timeUsedSeconds']) ?? 0,
    );
  }
}

/// What a goal banner shows, as T3 Code's `presentProviderGoal` words it.
class const AgentChatGoalPresentation({
  required final String title,
  required final String? usage,
  required final String objective,
  required final bool canResume,
}) {
  factory of(AgentChatGoal goal, {required bool working}) {
    final usage = <String>[
      if (goal.tokensUsed > 0)
        goal.tokenBudget == null
            ? '${agentChatGoalTokenLabel(goal.tokensUsed)} tokens'
            : '${agentChatGoalTokenLabel(goal.tokensUsed)} / '
                  '${agentChatGoalTokenLabel(goal.tokenBudget!)} tokens',
      if (goal.timeUsedSeconds >= 60)
        agentChatDurationLabel(Duration(seconds: goal.timeUsedSeconds)),
    ];
    return AgentChatGoalPresentation(
      title: switch (goal.status) {
        AgentChatGoalStatus.active => working ? 'Pursuing goal' : 'Goal set',
        AgentChatGoalStatus.paused => 'Goal paused',
        AgentChatGoalStatus.blocked => 'Goal blocked',
        AgentChatGoalStatus.usageLimited => 'Goal hit a usage limit',
        AgentChatGoalStatus.budgetLimited => 'Goal reached its token budget',
        AgentChatGoalStatus.complete => 'Goal complete',
      },
      usage: usage.isEmpty ? null : usage.join(' · '),
      objective: goal.objective,
      canResume:
          goal.status != AgentChatGoalStatus.active &&
          goal.status != AgentChatGoalStatus.complete,
    );
  }

  /// The banner's heading: the title, then the usage when there is any.
  String get heading => usage == null ? title : '$title · $usage';
}

/// "950", "12k", "1.5m": a token count as the goal banner shows it.
String agentChatGoalTokenLabel(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) return '${(tokens / 1000).round()}k';
  final millions = (tokens / 1000000).toStringAsFixed(1);
  return '${millions.endsWith('.0') ? millions.substring(0, millions.length - 2) : millions}m';
}

/// The composer text that resumes a paused goal.
const String agentChatGoalResumeCommand = '/goal resume';

/// The composer text that clears the goal.
const String agentChatGoalClearCommand = '/goal clear';
