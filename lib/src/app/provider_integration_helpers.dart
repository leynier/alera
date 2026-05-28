part of 'providers.dart';

Future<void> _showAgentStatusNotifications({
  required Ref ref,
  required AgentStatusNotificationPresenter presenter,
  required Future<void> Function() ensureInitialized,
  required List<AgentStatusEntry> entries,
}) async {
  await ensureInitialized();
  final state = ref.read(workbenchControllerProvider);
  for (final entry in entries) {
    final workspace = _findWorkspaceById(state, entry.workspaceId);
    final project = workspace == null
        ? null
        : _findProjectById(state, workspace.projectId);
    final tab = _findTabById(state, entry.workspaceId, entry.tabId);
    final notification = composeAgentStatusNotification(
      entry: entry,
      projectName: project?.name,
      workspaceName: workspace?.name,
      tabTitle: tab?.title,
    );
    if (notification == null) {
      continue;
    }
    await presenter.show(notification);
  }
}

TerminalHostConfig _terminalHostConfigFor(TerminalSettings settings) {
  return TerminalHostConfig(
    emptyShutdownDelaySeconds: settings.hostEmptyShutdownDelaySeconds,
    detachedSessionShutdownDelaySeconds:
        settings.hostDetachedSessionShutdownDelaySeconds,
    scrollbackBytes: settings.hostScrollbackBytes,
  );
}

List<AgentType> _enabledAgentStatusHookTypes(AgentStatusHookSettings settings) {
  return <AgentType>[
    if (settings.codex) AgentType.codex,
    if (settings.claude) AgentType.claude,
    if (settings.copilot) AgentType.copilot,
    if (settings.cursor) AgentType.cursor,
    if (settings.agy) AgentType.agy,
    if (settings.opencode) AgentType.opencode,
    if (settings.pi) AgentType.pi,
    if (settings.amp) AgentType.amp,
  ];
}

List<AgentType> _globalManagedAgentTypes() {
  return <AgentType>[
    for (final agentType in AgentType.values)
      if (agentType != AgentType.codex &&
          agentType != AgentType.claude &&
          agentType != AgentType.copilot &&
          agentType != AgentType.cursor &&
          agentType != AgentType.opencode &&
          agentType != AgentType.pi &&
          agentType != AgentType.amp)
        agentType,
  ];
}

List<AgentType> _enabledGlobalManagedAgentStatusHookTypes(
  AgentStatusHookSettings settings,
) {
  return <AgentType>[
    for (final agentType in _enabledAgentStatusHookTypes(settings))
      if (agentType != AgentType.codex &&
          agentType != AgentType.claude &&
          agentType != AgentType.copilot &&
          agentType != AgentType.cursor &&
          agentType != AgentType.opencode &&
          agentType != AgentType.pi &&
          agentType != AgentType.amp)
        agentType,
  ];
}

Future<List<ManagedAgentHookInstallStatus>> _reconcileAgentHooks({
  required ManagedAgentHookInstallService service,
  required CodexRuntimeHomeService codexRuntimeHome,
  required ClaudeRuntimeHomeService claudeRuntimeHome,
  required AgentStatusHookSettings settings,
}) async {
  final results = await service.reconcile(
    enabledAgentTypes: _enabledGlobalManagedAgentStatusHookTypes(settings),
    agentTypes: _globalManagedAgentTypes(),
  );
  results.add(
    settings.codex
        ? await codexRuntimeHome.install()
        : await codexRuntimeHome.remove(),
  );
  results.add(
    settings.claude
        ? await claudeRuntimeHome.install()
        : await claudeRuntimeHome.remove(),
  );
  results.add(service.remove(AgentType.opencode));
  results.add(service.remove(AgentType.pi));
  return results;
}

Future<Map<String, String>?> _terminalLaunchEnvironmentFor({
  required AgentHookReceiver agentHookReceiver,
  required CodexRuntimeHomeService codexRuntimeHome,
  required ClaudeRuntimeHomeService claudeRuntimeHome,
  required AgentRuntimeOverlayService agentRuntimeOverlay,
  required AgentStatusHookSettings hooks,
  required String terminalSessionId,
  required String workspaceId,
  required String tabId,
}) async {
  final environment = <String, String>{};
  final hookEnvironment = await agentHookReceiver.launchEnvironmentFor(
    terminalSessionId: terminalSessionId,
    workspaceId: workspaceId,
    tabId: tabId,
  );
  if (hookEnvironment != null) {
    environment.addAll(hookEnvironment);
  }
  if (hooks.copilot ||
      hooks.cursor ||
      hooks.opencode ||
      hooks.pi ||
      hooks.amp) {
    try {
      await agentRuntimeOverlay.clearTerminalOverlays(terminalSessionId);
    } catch (_) {}
  }
  if (hooks.codex) {
    try {
      final preparation = await codexRuntimeHome.prepareForTerminalLaunch();
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.claude) {
    try {
      final preparation = await claudeRuntimeHome.prepareForTerminalLaunch();
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.copilot) {
    try {
      final preparation = await agentRuntimeOverlay
          .prepareCopilotForTerminalLaunch(
            terminalSessionId: terminalSessionId,
          );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.cursor) {
    try {
      final preparation = await agentRuntimeOverlay
          .prepareCursorForTerminalLaunch(terminalSessionId: terminalSessionId);
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.opencode) {
    try {
      final preparation = await agentRuntimeOverlay
          .prepareOpenCodeForTerminalLaunch(
            terminalSessionId: terminalSessionId,
          );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.pi) {
    try {
      final preparation = await agentRuntimeOverlay.preparePiForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.amp) {
    try {
      final preparation = await agentRuntimeOverlay.prepareAmpForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  return environment.isEmpty ? null : environment;
}

bool _isAgentStatusHookEnabled(
  AgentStatusHookSettings settings,
  AgentType agentType,
) {
  return switch (agentType) {
    AgentType.codex => settings.codex,
    AgentType.claude => settings.claude,
    AgentType.copilot => settings.copilot,
    AgentType.cursor => settings.cursor,
    AgentType.agy => settings.agy,
    AgentType.opencode => settings.opencode,
    AgentType.pi => settings.pi,
    AgentType.amp => settings.amp,
  };
}

// coverage:ignore-start
void _ignoreProviderAsyncError(Object error, StackTrace stackTrace) {}
// coverage:ignore-end

class _RiverpodAgentNotificationWorkbenchNavigator
    implements AgentNotificationWorkbenchNavigator {
  _RiverpodAgentNotificationWorkbenchNavigator(this._ref);

  final Ref _ref;

  @override
  WorkbenchState get state => _ref.read(workbenchControllerProvider);

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) {
    return _ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspace(project: project, workspace: workspace);
  }

  @override
  void setActiveTab({required String workspaceId, required String tabId}) {
    _ref
        .read(workbenchControllerProvider.notifier)
        .setActiveTab(workspaceId: workspaceId, tabId: tabId);
  }
}

class _RiverpodAgentNotificationTerminalFocusRequester
    implements AgentNotificationTerminalFocusRequester {
  _RiverpodAgentNotificationTerminalFocusRequester(this._ref);

  final Ref _ref;

  @override
  void requestTerminalFocus({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    _ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: workspace, tab: tab)
        .requestFocus();
  }
}
