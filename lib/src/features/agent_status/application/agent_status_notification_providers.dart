part of 'agent_status_providers.dart';

@Riverpod(keepAlive: true)
AgentStatusNotificationPresenter agentStatusNotificationPresenter(Ref ref) {
  return DesktopAgentStatusNotificationService();
}

@Riverpod(keepAlive: true)
AgentNotificationWindowActivator agentStatusNotificationWindowActivator(
  Ref ref,
) {
  return const WindowManagerAgentWindowActivator();
}

@Riverpod(keepAlive: true)
AgentNotificationWorkbenchNavigator agentStatusNotificationWorkbenchNavigator(
  Ref ref,
) {
  return _RiverpodAgentNotificationWorkbenchNavigator(ref);
}

@Riverpod(keepAlive: true)
AgentNotificationTerminalFocusRequester
agentStatusNotificationTerminalFocusRequester(Ref ref) {
  return _RiverpodAgentNotificationTerminalFocusRequester(ref);
}

@Riverpod(keepAlive: true)
AgentStatusNotificationActivationService
agentStatusNotificationActivationService(Ref ref) {
  return AgentStatusNotificationActivationService(
    windowActivator: ref.watch(agentStatusNotificationWindowActivatorProvider),
    navigator: ref.watch(agentStatusNotificationWorkbenchNavigatorProvider),
    terminalFocusRequester: ref.watch(
      agentStatusNotificationTerminalFocusRequesterProvider,
    ),
  );
}

/// tests can collapse the window instead of waiting it out.
@Riverpod(keepAlive: true)
({Duration window, Duration maxDelay}) agentStatusNotificationCoalescing(
  Ref ref,
) {
  return (
    window: agentStatusNotificationCoalesceWindow,
    maxDelay: agentStatusNotificationMaxCoalesceDelay,
  );
}

@Riverpod(keepAlive: true)
void agentStatusNotificationCoordinator(Ref ref) {
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final activationService = ref.watch(
    agentStatusNotificationActivationServiceProvider,
  );
  final clock = ref.watch(agentStatusClockProvider);
  // Whatever the runtime is already holding when this coordinator comes up is
  // not something the user just caused: agent presence lives for the life of
  // the PTY, so the first snapshot after a launch or a host reconnect would
  // otherwise replay every waiting and finished agent in one burst.
  final tracker = AgentStatusNotificationTracker(
    now: clock,
    notifiableFrom: clock(),
  );
  var initialized = false;
  Future<void>? initializing;

  Future<void> ensureInitialized() async {
    if (initialized) {
      return;
    }
    initializing ??= presenter
        .initialize(
          onSelected: (payload) {
            unawaited(
              activationService
                  .activatePayload(payload)
                  .catchError(_ignoreProviderAsyncError),
            );
          },
        )
        .then<void>((_) {
          initialized = true;
        });
    await initializing;
  }

  final coalescing = ref.watch(agentStatusNotificationCoalescingProvider);
  final scheduler = AgentStatusNotificationScheduler(
    emit: (batch) => _showAgentStatusNotifications(
      ref: ref,
      presenter: presenter,
      ensureInitialized: ensureInitialized,
      entries: batch,
    ),
    coalesceWindow: coalescing.window,
    maxCoalesceDelay: coalescing.maxDelay,
    now: clock,
  );
  ref.onDispose(scheduler.dispose);

  // Settings are read rather than watched: rebuilding this provider whenever a
  // toggle moves would drop the tracker's delivery history along with it, and
  // every state the user already dismissed would notify again.
  AgentSettings agentSettings() => ref.read(settingsControllerProvider).agents;
  bool notificationsEnabled(AgentSettings agents) =>
      agents.agentStatusHooks.anyEnabled &&
      agents.agentStatusNotificationsEnabled;

  if (notificationsEnabled(agentSettings())) {
    unawaited(ensureInitialized().catchError(_ignoreProviderAsyncError));
  }
  ref.listen<bool>(
    settingsControllerProvider.select(
      (settings) => notificationsEnabled(settings.agents),
    ),
    (previous, next) {
      if (!next) {
        return;
      }
      // Initializing asks for the OS permission prompt, so it belongs to the
      // moment the user turns notifications on rather than to the first event.
      unawaited(ensureInitialized().catchError(_ignoreProviderAsyncError));
    },
  );

  ref.listen<Map<String, AgentStatusEntry>>(agentStatusControllerProvider, (
    previous,
    next,
  ) {
    final agents = agentSettings();
    if (!notificationsEnabled(agents)) {
      return;
    }
    final pending = tracker.pendingNotifications(
      previous: previous,
      next: Map<String, AgentStatusEntry>.fromEntries(
        next.entries.where(
          (entry) => isAgentStatusHookEnabled(
            agents.agentStatusHooks,
            entry.value.agentType,
          ),
        ),
      ),
      includeFinished: agents.agentStatusFinishedNotificationsEnabled,
    );
    if (pending.isEmpty) {
      return;
    }
    scheduler.enqueue(pending);
  });
}

Future<void> _showAgentStatusNotifications({
  required Ref ref,
  required AgentStatusNotificationPresenter presenter,
  required Future<void> Function() ensureInitialized,
  required List<AgentStatusEntry> entries,
}) async {
  await ensureInitialized();
  final state = ref.read(workbenchControllerProvider);
  final locations = <AgentStatusNotificationLocation>[];
  for (final entry in entries) {
    final workspace = findWorkspaceById(state, entry.workspaceId);
    final project = workspace == null
        ? null
        : findProjectById(state, workspace.projectId);
    final tab = findTabById(state, entry.workspaceId, entry.tabId);
    locations.add(
      AgentStatusNotificationLocation(
        entry: entry,
        projectName: project?.name,
        workspaceName: workspace?.name,
        tabTitle: tab?.title,
      ),
    );
  }
  final notification = composeAgentStatusNotifications(
    locations: locations,
    includeFinished: ref
        .read(settingsControllerProvider)
        .agents
        .agentStatusFinishedNotificationsEnabled,
  );
  if (notification == null) {
    return;
  }
  await presenter.show(notification);
}

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
