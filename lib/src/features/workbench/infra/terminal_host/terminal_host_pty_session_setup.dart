part of 'terminal_host_pty_session.dart';

extension _TerminalHostSetupLaunch on TerminalHostPtySession {
  Future<TerminalHostAttachment> _createOrAttachImpl() async {
    _observing = await _shouldObserve();
    final launch = _launch;
    final workingDirectory = _workingDirectory;
    final cols = _cols;
    final rows = _rows;
    if (launch == null ||
        workingDirectory == null ||
        cols == null ||
        rows == null) {
      throw StateError('PTY session has not been started.');
    }
    if (_providerSetup case final setup?) {
      return _providerSetupAttachment(
        setup,
        restart: false,
        launch: launch,
        workingDirectory: workingDirectory,
        cols: cols,
        rows: rows,
      );
    }
    return _client.createOrAttach(
      sessionId: _sessionId,
      workspaceId: _workspaceId,
      tabId: _tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: cols,
      rows: rows,
      observe: _observing,
    );
  }

  Future<void> _restartProcessImpl() async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    if (_observing) {
      throw StateError(
        'This automation terminal is read-only. Take over the run to restart it.',
      );
    }
    final launch = _launch;
    final workingDirectory = _workingDirectory;
    final cols = _cols;
    final rows = _rows;
    if (launch == null ||
        workingDirectory == null ||
        cols == null ||
        rows == null) {
      throw StateError('PTY session has not been started.');
    }
    final setup = _providerSetup;
    final attachment = setup != null
        ? await _providerSetupAttachment(
            setup,
            restart: true,
            launch: launch,
            workingDirectory: workingDirectory,
            cols: cols,
            rows: rows,
          )
        : await _client.restart(
            sessionId: _sessionId,
            workspaceId: _workspaceId,
            tabId: _tabId,
            workingDirectory: workingDirectory,
            launch: launch,
            cols: cols,
            rows: rows,
          );
    await _applyAttachment(attachment);
  }

  Future<TerminalHostAttachment> _providerSetupAttachment(
    CommandTerminalProviderSetup setup, {
    required bool restart,
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
  }) {
    final client = _client;
    if (client is! TerminalHostProviderSetupClient) {
      throw UnsupportedError('Provider setup requires the local runtime host.');
    }
    final setupClient = client as TerminalHostProviderSetupClient;
    return setupClient.providerSetupTerminal(
      sessionId: _sessionId,
      workspaceId: _workspaceId,
      tabId: _tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: cols,
      rows: rows,
      providerSetup: setup,
      hostId: _providerSetupHostId,
      restart: restart,
    );
  }
}
