import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_selection.dart';

enum AgentChatPickDecision { apply, confirmHandoff, blocked }

/// Provider changes use the host's idle guard and confirm only once the
/// conversation has started. Model-only picks never confirm a handoff.
AgentChatPickDecision agentChatPickDecision({
  required bool neverSent,
  required bool switchesProvider,
  required bool canSwitchProvider,
}) {
  if (!switchesProvider) return .apply;
  if (!canSwitchProvider) return .blocked;
  return neverSent ? .apply : .confirmHandoff;
}

/// One configuration preserves same-chat identity and explicitly resets the
/// model when the provider-default row is picked.
AgentChatConfiguration agentChatConfigurationForPick({
  required AgentChatProviderInstance target,
  required String? modelId,
  required String currentInstanceId,
}) => AgentChatSelection(
  providerInstanceId: target.id,
  model: modelId,
).configuration(switchProvider: target.id != currentInstanceId);
