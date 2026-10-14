import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/widgets.dart';

IconData agentChatRuntimeModeIcon(AgentChatRuntimeMode mode) => switch (mode) {
  AgentChatRuntimeMode.fullAccess => AleraIcons.warning,
  _ => AleraIcons.tune,
};

/// A short status for the composer chip: the model, or the provider when the
/// session has not reported one, and the plan mode when it is on.
String agentChatSettingsSummary({
  required String providerLabel,
  required String? model,
  required AgentChatInteractionMode interactionMode,
}) {
  final base = model ?? providerLabel;
  return interactionMode == AgentChatInteractionMode.plan
      ? '$base · Plan'
      : base;
}
