// coverage:ignore-file
// Codex user-config descriptors are intentionally inactive: Codex hooks are
// installed only in Alera-managed runtime homes.
part of '../managed_agent_hook_installer.dart';

extension _CodexManagedAgentHook on ManagedAgentHookInstallService {
  _AgentHookDescriptor _codexDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    return _AgentHookDescriptor(
      agentType: .codex,
      configPath: p.join(_homeDirectory, '.codex', 'hooks.json'),
      configLabel: 'Codex hooks.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_AGENT_HOOK_EVENT',
      configShape: .hooks,
      definitionShape: .nestedCommand,
      events: const <_ManagedHookEvent>[
        _ManagedHookEvent('SessionStart'),
        _ManagedHookEvent('UserPromptSubmit'),
        _ManagedHookEvent('PreToolUse'),
        _ManagedHookEvent('PostToolUse'),
        _ManagedHookEvent('PermissionRequest'),
        _ManagedHookEvent('Stop'),
      ],
    );
  }
}
