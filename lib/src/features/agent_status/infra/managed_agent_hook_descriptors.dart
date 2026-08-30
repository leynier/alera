part of 'managed_agent_hook_installer.dart';

extension _ManagedAgentHookDescriptors on ManagedAgentHookInstallService {
  ManagedAgentHookInstallStatus _codexRuntimeOnlyStatus() {
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.codex,
      state: ManagedAgentHookInstallState.notInstalled,
      configPath: p.join(_homeDirectory, '.codex', 'hooks.json'),
      managedHooksPresent: false,
      detail: 'Codex hooks are installed only in Alera-managed runtime homes.',
    );
  }

  ManagedAgentHookInstallStatus _claudeRuntimeOnlyStatus() {
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.claude,
      state: ManagedAgentHookInstallState.notInstalled,
      configPath: p.join(_homeDirectory, '.claude', 'settings.json'),
      managedHooksPresent: false,
      detail: 'Claude Code hooks are installed only in Alera-managed runtime homes.',
    );
  }

  ManagedAgentHookInstallStatus _cursorRuntimeOnlyStatus() {
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.cursor,
      state: ManagedAgentHookInstallState.notInstalled,
      configPath: p.join(_homeDirectory, '.cursor', 'hooks.json'),
      managedHooksPresent: false,
      detail: 'Cursor hooks are installed as a per-session plugin, never in this file.',
    );
  }

  ManagedAgentHookInstallStatus _fxRuntimeOnlyStatus() {
    return ManagedAgentHookInstallStatus(
      agentType: AgentType.fx,
      state: ManagedAgentHookInstallState.notInstalled,
      configPath: p.join(_homeDirectory, '.fx'),
      managedHooksPresent: false,
      detail: 'fx reports status through its built-in local Herdr integration, so no user hooks are installed.',
    );
  }

  _AgentHookDescriptor _descriptor(AgentType agentType) {
    final extension = switch ((agentType, _platform)) {
      (AgentType.copilot, ManagedAgentHookPlatform.windows) => 'ps1',
      (_, ManagedAgentHookPlatform.windows) => 'cmd',
      (_, ManagedAgentHookPlatform.posix) => 'sh',
    };
    final scriptFileName = 'alera-${agentType.key}-hook.$extension';
    final scriptPath = p.join(
      _homeDirectory,
      '.alera',
      'agent-hooks',
      scriptFileName,
    );
    return switch (agentType) {
      AgentType.codex => _codexDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.claude => _claudeDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.copilot => _copilotDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.agy => _agyDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.grok => _grokDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      // coverage:ignore-start
      // Descriptor lookups for artifact-backed agents are guarded by
      // _managedArtifact before this switch, and Cursor by its runtime-only
      // status. This branch protects future misuse.
      AgentType.cursor ||
      AgentType.opencode ||
      AgentType.opencode2 ||
      AgentType.pi ||
      AgentType.amp ||
      AgentType.fx => throw ArgumentError.value(
        agentType,
        'agentType',
        'This agent does not use a JSON hook descriptor.',
      ),
      // coverage:ignore-end
    };
  }

  _ManagedHookArtifact? _managedArtifact(AgentType agentType) {
    return switch (agentType) {
      AgentType.opencode => _opencodeArtifact(),
      AgentType.opencode2 => _opencode2Artifact(),
      AgentType.pi => _piArtifact(),
      AgentType.amp => _ampArtifact(),
      AgentType.codex ||
      AgentType.claude ||
      AgentType.copilot ||
      AgentType.cursor ||
      AgentType.agy ||
      AgentType.grok ||
      AgentType.fx => null,
    };
  }

  ManagedAgentHookInstallStatus _managedArtifactStatus(
    _ManagedHookArtifact artifact,
  ) {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.notInstalled,
        configPath: artifact.path,
        managedHooksPresent: false,
      );
    }
    late final String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      // coverage:ignore-start
      // File permission races are platform/filesystem dependent; status tests
      // cover missing, managed, stale, and unmanaged artifact contents.
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
      // coverage:ignore-end
    }
    if (!content.contains(_managedArtifactMarker)) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail:
            'Existing ${artifact.label} is not Alera-managed. Rename it before enabling this hook.',
      );
    }
    if (content == artifact.content) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.installed,
        configPath: artifact.path,
        managedHooksPresent: true,
      );
    }
    return ManagedAgentHookInstallStatus(
      agentType: artifact.agentType,
      state: ManagedAgentHookInstallState.partial,
      configPath: artifact.path,
      managedHooksPresent: true,
      detail: 'Managed ${artifact.label} needs to be updated.',
    );
  }

  ManagedAgentHookInstallStatus _removeManagedArtifact(
    _ManagedHookArtifact artifact,
  ) {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      return _managedArtifactStatus(artifact);
    }
    late final String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      // coverage:ignore-start
      // File permission races are platform/filesystem dependent; remove tests
      // cover the managed and unmanaged artifact paths.
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
      // coverage:ignore-end
    }
    if (!content.contains(_managedArtifactMarker)) {
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail:
            'Existing ${artifact.label} is not Alera-managed. Refusing to remove it.',
      );
    }
    file.deleteSync();
    return _managedArtifactStatus(artifact);
  }

  void _writeManagedArtifact(_ManagedHookArtifact artifact) {
    final file = File(artifact.path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.readAsStringSync() == artifact.content) {
      return;
    }
    final tmpPath = p.join(
      file.parent.path,
      '.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final tmp = File(tmpPath)..writeAsStringSync(artifact.content);
    tmp.renameSync(artifact.path);
  }
}
