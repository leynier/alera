part of 'terminal_runtime.dart';

class XtermTerminalRuntime implements TerminalRuntime {
  factory XtermTerminalRuntime({
    TerminalPtySessionFactory? ptySessionFactory,
    TerminalSettings? initialSettings,
    ExternalUriLauncher? externalUriLauncher,
    List<GhosttyTerminalShellLaunch> Function()? shellLaunchesBuilder,
    TerminalLaunchEnvironmentBuilder? agentHookEnvironmentBuilder,
    TerminalShellStartupPreparer? shellStartupPreparer,
    TerminalSessionCleanup? terminalSessionCleanup,
    TerminalProcessCreated? terminalProcessCreated,
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
    );
  }

  XtermTerminalRuntime._(
    this._ptySessionFactory,
    this._settings,
    this._externalUriLauncher,
    this._shellLaunchesBuilder,
    this._agentHookEnvironmentBuilder,
    this._shellStartupPreparer,
    this._terminalSessionCleanup,
    this._terminalProcessCreated,
  );

  final TerminalPtySessionFactory _ptySessionFactory;
  final ExternalUriLauncher _externalUriLauncher;
  final List<GhosttyTerminalShellLaunch> Function() _shellLaunchesBuilder;
  final TerminalLaunchEnvironmentBuilder? _agentHookEnvironmentBuilder;
  final TerminalShellStartupPreparer? _shellStartupPreparer;
  final TerminalSessionCleanup? _terminalSessionCleanup;
  final TerminalProcessCreated? _terminalProcessCreated;
  TerminalSettings _settings;
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final Map<String, _XtermTerminalSessionHandle> _sessions =
      <String, _XtermTerminalSessionHandle>{};

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  void updateSettings(TerminalSettings settings) {
    _settings = settings;
    for (final session in _sessions.values) {
      session.applySettings(settings);
    }
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions
        .putIfAbsent(tab.id, () {
          return _XtermTerminalSessionHandle(
            workspace,
            tab,
            _ptySessionFactory,
            _settings,
            _externalUriLauncher,
            _shellLaunchesBuilder,
            _agentHookEnvironmentBuilder,
            _shellStartupPreparer,
            _terminalProcessCreated,
            _handleSessionExit,
          );
        })
        .sync(workspace: workspace, tab: tab);
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
