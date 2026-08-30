part of '../managed_agent_hook_installer.dart';

extension _GrokManagedAgentHook on ManagedAgentHookInstallService {
  _AgentHookDescriptor _grokDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    final configuredHome = _environment['GROK_HOME']?.trim();
    final grokHome = configuredHome != null && configuredHome.isNotEmpty
        ? configuredHome
        : p.join(_homeDirectory, '.grok');
    return _AgentHookDescriptor(
      agentType: .grok,
      configPath: p.join(grokHome, 'hooks', 'alera-status.json'),
      configLabel: 'Grok Build alera-status.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_GROK_EVENT',
      configShape: .hooks,
      definitionShape: .nestedCommand,
      events: const <_ManagedHookEvent>[
        _ManagedHookEvent('SessionStart'),
        _ManagedHookEvent('UserPromptSubmit'),
        _ManagedHookEvent('PreToolUse', matcher: '*'),
        _ManagedHookEvent('PostToolUse', matcher: '*'),
        _ManagedHookEvent('PostToolUseFailure', matcher: '*'),
        _ManagedHookEvent('Notification'),
        _ManagedHookEvent('Stop'),
        _ManagedHookEvent('StopFailure'),
        _ManagedHookEvent('SessionEnd'),
      ],
    );
  }
}
