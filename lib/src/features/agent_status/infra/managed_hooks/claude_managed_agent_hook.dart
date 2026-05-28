// coverage:ignore-file
// Claude user-config descriptors are intentionally inactive: Claude hooks are
// installed only in Alera-managed runtime homes.
part of '../managed_agent_hook_installer.dart';

extension _ClaudeManagedAgentHook on ManagedAgentHookInstallService {
  _AgentHookDescriptor _claudeDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    return _AgentHookDescriptor(
      agentType: AgentType.claude,
      configPath: p.join(_homeDirectory, '.claude', 'settings.json'),
      configLabel: 'Claude settings.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_AGENT_HOOK_EVENT',
      configShape: _AgentHookConfigShape.hooks,
      definitionShape: _ManagedHookDefinitionShape.nestedCommand,
      events: const <_ManagedHookEvent>[
        _ManagedHookEvent('UserPromptSubmit'),
        _ManagedHookEvent('Stop'),
        _ManagedHookEvent('PreToolUse', matcher: '*'),
        _ManagedHookEvent('PostToolUse', matcher: '*'),
        _ManagedHookEvent('PostToolUseFailure', matcher: '*'),
        _ManagedHookEvent('PermissionRequest', matcher: '*'),
      ],
    );
  }
}
