part of '../managed_agent_hook_installer.dart';

extension _CopilotManagedAgentHook on ManagedAgentHookInstallService {
  _AgentHookDescriptor _copilotDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    return _AgentHookDescriptor(
      agentType: .copilot,
      configPath: p.join(_copilotHome(), 'hooks', 'alera.json'),
      configLabel: 'Copilot hooks/alera.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_COPILOT_HOOK_EVENT',
      configShape: .hooks,
      definitionShape: .directCommand,
      events: const <_ManagedHookEvent>[
        _ManagedHookEvent('SessionStart'),
        _ManagedHookEvent('SessionEnd'),
        _ManagedHookEvent('UserPromptSubmit'),
        _ManagedHookEvent('PreToolUse'),
        _ManagedHookEvent('PostToolUse'),
        _ManagedHookEvent('PostToolUseFailure'),
        _ManagedHookEvent('subagentStart'),
        _ManagedHookEvent('SubagentStop'),
        _ManagedHookEvent('PreCompact'),
        _ManagedHookEvent('Stop'),
        _ManagedHookEvent('ErrorOccurred'),
        _ManagedHookEvent('PermissionRequest'),
        _ManagedHookEvent('Notification'),
      ],
    );
  }

  String _copilotHome() {
    final fromEnv = _environment['COPILOT_HOME']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return p.join(_homeDirectory, '.copilot');
  }
}
