part of 'terminal_runtime.dart';

class XtermTerminalRuntime._(
  final TerminalPtySessionFactory _ptySessionFactory,
  var TerminalSettings _settings,
  final ExternalUriLauncher _externalUriLauncher,
  final List<GhosttyTerminalShellLaunch> Function() _shellLaunchesBuilder,
  final TerminalLaunchEnvironmentBuilder? _agentHookEnvironmentBuilder,
  final TerminalShellStartupPreparer? _shellStartupPreparer,
  final TerminalSessionCleanup? _terminalSessionCleanup,
  final TerminalProcessCreated? _terminalProcessCreated,
  final TerminalClipboard _terminalClipboard,
  final void Function(String message, {bool error})? _interactionNotice,
) implements TerminalRuntime {
  factory({
    TerminalPtySessionFactory? ptySessionFactory,
    TerminalSettings? initialSettings,
    ExternalUriLauncher? externalUriLauncher,
    List<GhosttyTerminalShellLaunch> Function()? shellLaunchesBuilder,
    TerminalLaunchEnvironmentBuilder? agentHookEnvironmentBuilder,
    TerminalShellStartupPreparer? shellStartupPreparer,
    TerminalSessionCleanup? terminalSessionCleanup,
    TerminalProcessCreated? terminalProcessCreated,
    TerminalClipboard? terminalClipboard,
    void Function(String message, {bool error})? interactionNotice,
  }) {
    return XtermTerminalRuntime._(
      ptySessionFactory ?? const DefaultTerminalPtySessionFactory(),
      initialSettings ?? TerminalSettings.defaults,
      externalUriLauncher ?? UrlLauncherExternalUriLauncher(),
      shellLaunchesBuilder ?? _terminalShellLaunches,
      agentHookEnvironmentBuilder,
      shellStartupPreparer,
      terminalSessionCleanup,
      terminalProcessCreated,
      terminalClipboard ?? const NativeTerminalClipboard(),
      interactionNotice,
    );
  }

  String? _activeWorkspaceId;
  bool _appForeground = true;
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final Map<String, _XtermTerminalSessionHandle> _sessions =
      <String, _XtermTerminalSessionHandle>{};
  bool _osc52BlockedNoticeShown = false;

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  void updateSettings(TerminalSettings settings) {
    _settings = settings;
    for (final session in _sessions.values) {
      session.applySettings(settings);
    }
    // Lowering the budget in settings has to take effect now, not at the next
    // workspace switch.
    _enforceBufferBudget();
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions
        .putIfAbsent(tab.id, () {
          final handle = _XtermTerminalSessionHandle(
            workspace,
            tab,
            _ptySessionFactory,
            _settings,
            _externalUriLauncher,
            _shellLaunchesBuilder,
            _agentHookEnvironmentBuilder,
            _shellStartupPreparer,
            _terminalProcessCreated,
            _terminalClipboard,
            _interactionNotice,
            _notifyOsc52Blocked,
            _handleSessionExit,
            _handleVisibilityChanged,
          )..setAppForeground(_appForeground);
          // Apply only at session creation so toggling the setting later does
          // not reopen composers the user already closed.
          if (_settings.showComposerByDefault) {
            handle.composerController.show();
          }
          return handle;
        })
        .sync(workspace: workspace, tab: tab);
  }

  @override
  TerminalSessionHandle? peekSession(String tabId) => _sessions[tabId];

  @override
  void setActiveWorkspace(String? workspaceId) {
    if (_activeWorkspaceId == workspaceId) {
      return;
    }
    _activeWorkspaceId = workspaceId;
    _enforceBufferBudget();
  }

  /// Parks terminal delivery and frame scheduling while the desktop window is
  /// hidden. The sidecar keeps the PTY and its bounded scrollback alive, then
  /// resynchronises from the delivery cursor when the window returns.
  void setAppForeground(bool foreground) {
    if (_appForeground == foreground) {
      return;
    }
    _appForeground = foreground;
    for (final session in _sessions.values) {
      session.setAppForeground(foreground);
    }
  }

  void _handleVisibilityChanged(_XtermTerminalSessionHandle handle) {
    if (handle.isVisible) {
      return;
    }
    // A terminal going off screen is the only moment a new eviction candidate
    // appears, so this is the sweep trigger rather than a timer.
    _enforceBufferBudget();
  }

  /// Detaches the coldest terminals until the estimated buffer total fits.
  ///
  /// Eviction never terminates the PTY, so the agent keeps running on the host
  /// and the scrollback is restored from the host snapshot on return.
  void _enforceBufferBudget() {
    final budget = TerminalBufferBudget(
      budgetBytes: _settings.bufferBudgetMegabytes * 1024 * 1024,
    );
    if (budget.isUnbounded || _sessions.isEmpty) {
      return;
    }
    final pinned = <String>{
      for (final entry in _sessions.entries)
        if (entry.value.isVisible) entry.key,
    };
    final evictions = budget.selectEvictions(
      live: <TerminalBufferUsage>[
        for (final session in _sessions.values) session.bufferUsage,
      ],
      pinnedTabIds: pinned,
    );
    for (final tabId in evictions) {
      final session = _sessions.remove(tabId);
      if (session != null) {
        _disposeSession(session, terminatePty: false);
      }
    }
  }

  void _notifyOsc52Blocked() {
    if (_osc52BlockedNoticeShown) {
      return;
    }
    _osc52BlockedNoticeShown = true;
    _interactionNotice?.call(
      'Terminal clipboard write blocked. Enable OSC 52 clipboard writes in terminal settings.',
    );
  }

  void _handleSessionExit(TerminalRuntimeExitEvent event) {
    if (!_exitController.isClosed) {
      _exitController.add(event);
    }
  }

  @override
  void closeTab(String tabId) {
    final session = _sessions.remove(tabId);
    if (session != null) {
      _disposeSession(session, terminatePty: true);
    }
  }

  @override
  void closeWorkspace(String workspaceId) {
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      final session = _sessions.remove(tabId);
      if (session != null) {
        _disposeSession(session, terminatePty: true);
      }
    }
  }

  @override
  void releaseTab(String tabId) {
    final session = _sessions.remove(tabId);
    if (session != null) {
      _disposeSession(session, terminatePty: false);
    }
  }

  @override
  void releaseWorkspace(String workspaceId) {
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      releaseTab(tabId);
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      _disposeSession(session, terminatePty: false);
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }

  void _disposeSession(
    _XtermTerminalSessionHandle session, {
    required bool terminatePty,
  }) {
    final terminalSessionId = session.terminalSessionId;
    session.dispose(terminatePty: terminatePty);
    final cleanup = _terminalSessionCleanup;
    if (terminatePty && cleanup != null) {
      unawaited(
        Future<void>.sync(() => cleanup(terminalSessionId)).catchError((_) {}),
      );
    }
  }
}
