part of '../managed_agent_hook_installer.dart';

extension _CursorManagedAgentHook on ManagedAgentHookInstallService {
  _AgentHookDescriptor _cursorDescriptor({
    required String scriptFileName,
    required String scriptPath,
  }) {
    return _AgentHookDescriptor(
      agentType: AgentType.cursor,
      configPath: p.join(_homeDirectory, '.cursor', 'hooks.json'),
      configLabel: 'Cursor hooks.json',
      scriptFileName: scriptFileName,
      scriptPath: scriptPath,
      eventEnvVar: 'ALERA_CURSOR_HOOK_EVENT',
      configShape: _AgentHookConfigShape.hooks,
      definitionShape: _ManagedHookDefinitionShape.topLevelCommand,
      events: const <_ManagedHookEvent>[
        _ManagedHookEvent('beforeSubmitPrompt'),
        _ManagedHookEvent('stop'),
        _ManagedHookEvent('preToolUse'),
        _ManagedHookEvent('postToolUse'),
        _ManagedHookEvent('postToolUseFailure'),
        _ManagedHookEvent('beforeShellExecution'),
        _ManagedHookEvent('beforeMCPExecution'),
        _ManagedHookEvent('afterAgentResponse'),
      ],
    );
  }
}
