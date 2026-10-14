part of 'terminal_runtime.dart';

extension _TerminalSessionLaunch on _XtermTerminalSessionHandle {
  Future<bool> _startPtySession() async {
    final setupValue = _tab.payload[commandTerminalProviderSetupPayloadKey];
    final setup = setupValue == null
        ? null
        : CommandTerminalProviderSetup.fromJson(setupValue);
    final launches = _shellLaunchesBuilder();
    if (launches.isEmpty) {
      throw StateError(_noTerminalShellCandidatesMessage());
    }
    final agentHookEnvironment = await _agentHookEnvironmentBuilder?.call(
      terminalSessionId: _tab.terminalSessionId,
      workspaceId: _workspace.id,
      tabId: _tab.id,
    );
    Object? lastError;
    for (final launch in launches) {
      final session = _ptySessionFactory.create(
        sessionId: _tab.terminalSessionId,
        workspaceId: _workspace.id,
        tabId: _tab.id,
      );
      final generation = ++_ptyGeneration;
      final sub = session.events.listen(
        (event) => _handlePtySessionEvent(event, generation),
      );
      _activePtyGeneration = generation;
      try {
        if (setup != null) {
          if (session is! ProviderSetupTerminalPtySession) {
            throw UnsupportedError(
              'Provider setup requires the local runtime host.',
            );
          }
          session.configureProviderSetup(
            setup,
            hostId: _tab.payload[commandTerminalHostIdPayloadKey] as String?,
          );
        }
        final sanitizedLaunch = _launchWithSanitizedAgentHookEnvironment(
          _settings.resolvedLoginShell ? _launchAsLoginShell(launch) : launch,
          agentHookEnvironment,
        );
        final workspaceAwarePowerShellLaunch =
            _isWindowsPowerShellLaunch(sanitizedLaunch)
            ? _launchInWorkingDirectory(sanitizedLaunch, _workspace.path)
            : null;
        final preparedLaunch = await _shellStartupPreparer?.prepare(
          workspaceAwarePowerShellLaunch ?? sanitizedLaunch,
        );
        final interactiveLaunch =
            preparedLaunch ?? workspaceAwarePowerShellLaunch ?? sanitizedLaunch;
        final workspaceLaunch = workspaceAwarePowerShellLaunch == null
            ? _launchInWorkingDirectory(interactiveLaunch, _workspace.path)
            : interactiveLaunch;
        await session.start(
          launch: workspaceLaunch,
          workingDirectory: _workspace.path,
          cols: _terminal.viewWidth,
          rows: _terminal.viewHeight,
          onProcessCreated: () async {
            bool isCurrent() =>
                !_disposed && _activePtyGeneration == generation;
            if (!isCurrent()) {
              return;
            }
            await _terminalProcessCreated?.call(_tab.terminalSessionId);
            if (!isCurrent()) {
              return;
            }
            if (setup != null) return;
            await _deliverTerminalProcessStartup(
              session: session,
              launch: workspaceLaunch,
              interactiveShell: interactiveLaunch.shell,
              initialCommand:
                  (session is StartupCommandTerminalPtySession
                      ? session.initialCommandOverride
                      : null) ??
                  _tab.initialCommand,
              isCurrent: isCurrent,
            );
          },
        );
        if (_disposed || _activePtyGeneration != generation) {
          unawaited(sub.cancel());
          session.dispose();
          _prunePtyGenerationState();
          return false;
        }
        _ptySession = session;
        _ptySessionSub = sub;
        bool isCurrent() =>
            !_disposed &&
            _activePtyGeneration == generation &&
            identical(_ptySession, session);
        await _refreshTerminalPulseState(session, isCurrent: isCurrent);
        if (!isCurrent()) {
          unawaited(sub.cancel());
          session.dispose();
          _prunePtyGenerationState();
          return false;
        }
        if (!_outputVisible) {
          _syncPtyOutputVisibility();
        }
        _flushPendingPtyResize();
        _running = !_exitedPtyGenerations.contains(generation);
        _prunePtyGenerationState();
        _notifySessionListeners();
        return !_disposed &&
            _activePtyGeneration == generation &&
            identical(_ptySession, session);
      } catch (error) {
        if (_disposed || _activePtyGeneration != generation) {
          unawaited(sub.cancel());
          session.dispose();
          _prunePtyGenerationState();
          return false;
        }
        lastError = error;
        _suppressedExitPtyGenerations.add(generation);
        if (_activePtyGeneration == generation) {
          _activePtyGeneration = null;
        }
        if (identical(_ptySession, session)) {
          _ptySession = null;
        }
        if (identical(_ptySessionSub, sub)) {
          _ptySessionSub = null;
        }
        unawaited(sub.cancel());
        session.dispose();
        _prunePtyGenerationState();
        if (setup != null) rethrow;
      }
    }
    throw StateError('No desktop PTY shell could be started: $lastError');
  }

  void _handlePtySessionEvent(TerminalPtySessionEvent event, int generation) {
    if (_disposed || generation != _activePtyGeneration) {
      return;
    }
    switch (event) {
      // Output that arrives while hidden is queued, not dropped. The host
      // counts a frame as delivered the moment the client's queue takes it, so
      // discarding between losing visibility and the pause taking effect would
      // leave a gap that no later resume knows to resend.
      case TerminalPtyOutputEvent(:final data):
        _ptyOutputController.add(data);
      case TerminalPtyOutputTextEvent(:final text):
        // Already decoded by the reader isolate, so it skips the local
        // decoder entirely.
        _handleTerminalOutput(text);
      case TerminalPtySnapshotEvent(
        :final data,
        :final resetInteractionModes,
        :final text,
      ):
        _pendingInteractionModeReset |= resetInteractionModes;
        if (_outputVisible) {
          final shouldResetInteractionModes = _pendingInteractionModeReset;
          _preparePointerInputForSnapshot();
          _replaceTerminalWithSnapshot(
            data,
            text: text,
            resetInteractionModes: shouldResetInteractionModes,
          );
          _completePointerInputSnapshotCatchUp();
          _pendingInteractionModeReset = false;
        }
      case TerminalPtyExitEvent(:final exitCode):
        _handlePtyExit(
          exitCode: exitCode,
          generation: generation,
          notifyRuntime: event.notifyRuntime,
          cause: event.cause,
        );
      case TerminalPtyErrorEvent(:final error):
        _setTerminalHostError(error);
      case TerminalPtyPulseChangedEvent(:final state):
        _handleTerminalPulseChanged(state);
    }
  }

  void _handlePtyExit({
    required int exitCode,
    required int generation,
    required bool notifyRuntime,
    required TerminalExitCause cause,
  }) {
    if (!_exitedPtyGenerations.add(generation)) {
      return;
    }
    _running = false;
    _markTerminalPulseDisarmed();
    _flushPendingTerminalOutputNow();
    _writeToTerminal(terminalInteractionModeReset);
    _writeToTerminal('\n[process exited: $exitCode]\n');
    _notifySessionListeners();
    if (notifyRuntime && !_suppressedExitPtyGenerations.contains(generation)) {
      _onExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspaceId,
          tabId: tabId,
          exitCode: exitCode,
          autoCloseOnSuccess: _tab.autoCloseOnSuccess,
          cause: cause,
        ),
      );
    }
    unawaited(_stopPtySessionWithMode(suppressExit: true, terminate: false));
  }
}
