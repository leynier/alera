/// `AgentIdentityIcon` key for a chat provider. Chats reuse the glyphs the
/// terminal agents already have; providers name a few of them differently.
String agentChatAgentType(String provider) => switch (provider) {
  'claudeAgent' => 'claude',
  'antigravity' => 'agy',
  _ => provider,
};

/// Readable provider name for hints when the runtime gave no label.
String agentChatProviderName(String provider) => switch (provider) {
  'codex' => 'Codex',
  'claudeAgent' => 'Claude',
  'cursor' => 'Cursor',
  'grok' => 'Grok',
  'opencode' => 'OpenCode',
  'antigravity' => 'Antigravity',
  'pi' => 'Pi',
  'muse' => 'Muse',
  _ => 'the agent',
};
