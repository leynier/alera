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
      detail:
          'Claude Code hooks are installed only in Alera-managed runtime homes.',
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
      AgentType.cursor => _cursorDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.agy => _agyDescriptor(
        scriptFileName: scriptFileName,
        scriptPath: scriptPath,
      ),
      AgentType.opencode ||
      AgentType.pi ||
      AgentType.amp => throw ArgumentError.value(
        agentType,
        'agentType',
        'Managed artifact agents do not use JSON hook descriptors.',
      ),
    };
  }

  _ManagedHookArtifact? _managedArtifact(AgentType agentType) {
    return switch (agentType) {
      AgentType.opencode => _opencodeArtifact(),
      AgentType.pi => _piArtifact(),
      AgentType.amp => _ampArtifact(),
      AgentType.codex ||
      AgentType.claude ||
      AgentType.copilot ||
      AgentType.cursor ||
      AgentType.agy => null,
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
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
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
      return ManagedAgentHookInstallStatus(
        agentType: artifact.agentType,
        state: ManagedAgentHookInstallState.error,
        configPath: artifact.path,
        managedHooksPresent: false,
        detail: 'Could not read ${artifact.label}.',
      );
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
