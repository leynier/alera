import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';

/// The host-owned chat binding of an `agentChat` tab.
extension AgentChatTabRecord on WorkspaceTabRecord {
  String? get agentChatId =>
      _payloadString(AgentChatWire.chatIdKey) ??
      _payloadString(AgentChatWire.legacyChatIdKey);

  String? get agentChatProvider => _payloadString(AgentChatWire.providerKey);

  String? get agentChatModel => _payloadString(AgentChatWire.modelKey);

  String? _payloadString(String key) {
    final value = payload[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }
}

/// The agent mark shown for a chat provider; `null` for providers without a
/// bundled mark, which fall back to the generic agent icon.
AgentType? agentChatAgentType(String provider) => switch (provider) {
  'codex' => AgentType.codex,
  'claudeAgent' => AgentType.claude,
  'cursor' => AgentType.cursor,
  'grok' => AgentType.grok,
  'opencode' => AgentType.opencode,
  'antigravity' => AgentType.agy,
  'pi' => AgentType.pi,
  _ => null,
};

/// A readable provider name when the runtime's catalog is not loaded yet.
String agentChatProviderFallbackLabel(String provider) => switch (provider) {
  'codex' => 'Codex',
  'claudeAgent' => 'Claude',
  'cursor' => 'Cursor',
  'grok' => 'Grok',
  'opencode' => 'OpenCode',
  'antigravity' => 'Antigravity',
  'pi' => 'Pi',
  'muse' => 'Muse',
  'acpRegistry' => 'ACP Agent',
  '' => 'Agent',
  _ => provider,
};
