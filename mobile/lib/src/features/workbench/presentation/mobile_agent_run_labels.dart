import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';

/// Primary label for a workspace agent row. Matches the desktop tab title
/// when the host sent one; never falls back to activity text.
String mobileAgentRunTitle(AgentPresenceSummary status) {
  final title = status.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  return agentDisplayName(status.agentType);
}

/// Tool or assistant activity for the secondary line. Null when there is
/// nothing to show besides the title.
String? mobileAgentRunActivity(AgentPresenceSummary status) {
  final activity = _mobileAgentRunActivityText(status);
  if (activity == null || activity == mobileAgentRunTitle(status)) {
    return null;
  }
  return activity;
}

String? _mobileAgentRunActivityText(AgentPresenceSummary status) {
  if (status.state == 'working') {
    final toolName = status.toolName?.trim() ?? '';
    final toolInput = status.toolInput?.trim() ?? '';
    if (toolName.isNotEmpty && toolInput.isNotEmpty) {
      return '$toolName: $toolInput';
    }
    if (toolName.isNotEmpty) {
      return toolName;
    }
  }
  final assistantMessage = status.lastAssistantMessage?.trim() ?? '';
  if (assistantMessage.isEmpty) {
    return null;
  }
  return assistantMessage;
}
