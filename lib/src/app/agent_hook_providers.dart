part of 'providers.dart';

final agentHookReceiverProvider = Provider<AgentHookReceiver>((ref) {
  final receiver = AgentHookReceiver(
    statusSink: ref.read(agentStatusControllerProvider.notifier),
    isAgentEnabled: (agentType) => _isAgentStatusHookEnabled(
      ref.read(settingsControllerProvider).general.agentStatusHooks,
      agentType,
    ),
  );
  ref.onDispose(() {
    unawaited(receiver.dispose());
  });
  return receiver;
});

final managedAgentHookInstallServiceProvider =
    Provider<ManagedAgentHookInstallService>((ref) {
      return ManagedAgentHookInstallService();
    });

final codexRuntimeHomeServiceProvider = Provider<CodexRuntimeHomeService>((
  ref,
) {
  return CodexRuntimeHomeService();
});

final claudeRuntimeHomeServiceProvider = Provider<ClaudeRuntimeHomeService>((
  ref,
) {
  return ClaudeRuntimeHomeService();
});

final agentRuntimeOverlayServiceProvider = Provider<AgentRuntimeOverlayService>(
  (ref) {
    return AgentRuntimeOverlayService();
  },
);

final agentStatusNotificationPresenterProvider =
    Provider<AgentStatusNotificationPresenter>((ref) {
      return DesktopAgentStatusNotificationService();
    });

final agentNotificationWindowActivatorProvider =
    Provider<AgentNotificationWindowActivator>((ref) {
      return const WindowManagerAgentWindowActivator();
    });

final agentNotificationWorkbenchNavigatorProvider =
    Provider<AgentNotificationWorkbenchNavigator>((ref) {
      return _RiverpodAgentNotificationWorkbenchNavigator(ref);
    });

final agentNotificationTerminalFocusRequesterProvider =
    Provider<AgentNotificationTerminalFocusRequester>((ref) {
      return _RiverpodAgentNotificationTerminalFocusRequester(ref);
    });

final agentStatusNotificationActivationServiceProvider =
    Provider<AgentStatusNotificationActivationService>((ref) {
      return AgentStatusNotificationActivationService(
        windowActivator: ref.watch(agentNotificationWindowActivatorProvider),
        navigator: ref.watch(agentNotificationWorkbenchNavigatorProvider),
        terminalFocusRequester: ref.watch(
          agentNotificationTerminalFocusRequesterProvider,
        ),
      );
    });

final agentHookReceiverLifecycleProvider = Provider<void>((ref) {
  final enabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusHooks.anyEnabled,
    ),
  );
  final receiver = ref.watch(agentHookReceiverProvider);
  if (enabled) {
    unawaited(receiver.start().catchError(_ignoreProviderAsyncError));
  } else {
    unawaited(receiver.stop().catchError(_ignoreProviderAsyncError));
  }
});

final agentHookInstallerCoordinatorProvider = Provider<void>((ref) {
  final service = ref.watch(managedAgentHookInstallServiceProvider);
  final codexRuntimeHome = ref.watch(codexRuntimeHomeServiceProvider);
  final claudeRuntimeHome = ref.watch(claudeRuntimeHomeServiceProvider);
  ref.listen<AgentStatusHookSettings>(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusHooks,
    ),
    (previous, next) {
      if (previous == null || previous == next) {
        return;
      }
      final operation = _reconcileAgentHooks(
        service: service,
        codexRuntimeHome: codexRuntimeHome,
        claudeRuntimeHome: claudeRuntimeHome,
        settings: next,
      );
      unawaited(
        operation.then<void>((_) {}).catchError(_ignoreProviderAsyncError),
      );
    },
  );
});

final agentStatusNotificationCoordinatorProvider = Provider<void>((ref) {
  final hooksEnabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusHooks.anyEnabled,
    ),
  );
  final notificationsEnabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusNotificationsEnabled,
    ),
  );
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final activationService = ref.watch(
    agentStatusNotificationActivationServiceProvider,
  );
  final tracker = AgentStatusNotificationTracker();
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

  if (hooksEnabled && notificationsEnabled) {
    unawaited(ensureInitialized().catchError(_ignoreProviderAsyncError));
  }

  ref.listen<Map<String, AgentStatusEntry>>(agentStatusControllerProvider, (
    previous,
    next,
  ) {
    if (!hooksEnabled || !notificationsEnabled) {
      return;
    }
    final pending = tracker.pendingNotifications(
      previous: previous,
      next: Map<String, AgentStatusEntry>.fromEntries(
        next.entries.where(
          (entry) => _isAgentStatusHookEnabled(
            ref.read(settingsControllerProvider).general.agentStatusHooks,
            entry.value.agentType,
          ),
        ),
      ),
    );
    if (pending.isEmpty) {
      return;
    }
    unawaited(
      _showAgentStatusNotifications(
        ref: ref,
        presenter: presenter,
        ensureInitialized: ensureInitialized,
        entries: pending,
      ).catchError(_ignoreProviderAsyncError),
    );
  });
});
