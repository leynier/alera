import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/widgets.dart';

String agentChatRuntimeModeLabel(AgentChatRuntimeMode mode) => switch (mode) {
  AgentChatRuntimeMode.approvalRequired => 'Ask For Approval',
  AgentChatRuntimeMode.autoAcceptEdits => 'Accept Edits',
  AgentChatRuntimeMode.auto => 'Auto',
  AgentChatRuntimeMode.fullAccess => 'Full Access',
};

String agentChatRuntimeModeDescription(AgentChatRuntimeMode mode) =>
    switch (mode) {
      AgentChatRuntimeMode.approvalRequired =>
        'Ask before running commands or changing files.',
      AgentChatRuntimeMode.autoAcceptEdits =>
        'Change files in the workspace without asking; ask for the rest.',
      AgentChatRuntimeMode.auto =>
        'Only ask for actions the agent considers risky.',
      AgentChatRuntimeMode.fullAccess =>
        'Run commands, use the network and change files without asking.',
    };

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
