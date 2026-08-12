part of 'terminal_runtime.dart';

mixin _TerminalSessionCapabilitiesSupport on TerminalSessionHandle {
  WorkspaceTabRecord get _tab;

  TerminalPtySession? get _ptySession;

  void _notifyInteraction(String message, {bool error = false});

  late final ValueNotifier<TerminalPulseState> _terminalPulseNotifier =
      ValueNotifier<TerminalPulseState>(
        TerminalPulseState(configuration: _tab.terminalPulse, armed: false),
      );

  @override
  bool get canRestart {
    final session = _ptySession;
    return session is RecoverableTerminalPtySession && session.supportsRestart;
  }

  @override
  bool get supportsTerminalPulse {
    final session = _ptySession;
    return isRunning &&
        session is TerminalPulsePtySession &&
        session.supportsTerminalPulse;
  }

  @override
  ValueListenable<TerminalPulseState> get terminalPulseState =>
      _terminalPulseNotifier;

  @override
  Future<void> configureTerminalPulse({
    required TerminalPulseConfiguration configuration,
    required bool armed,
  }) async {
    await ensureStarted();
    final session = _ptySession;
    if (session is! TerminalPulsePtySession || !session.supportsTerminalPulse) {
      throw UnsupportedError(
        'The running terminal host does not support Terminal Pulse.',
      );
    }
    final state = await session.configureTerminalPulse(
      configuration: configuration,
      armed: armed,
    );
    _terminalPulseNotifier.value = identical(_ptySession, session) && isRunning
        ? state
        : TerminalPulseState(configuration: state.configuration, armed: false);
    notifyListeners();
  }

  void _syncTerminalPulseConfiguration(WorkspaceTabRecord tab) {
    final pulse = _terminalPulseNotifier.value;
    if (pulse.configuration == tab.terminalPulse) {
      return;
    }
    _terminalPulseNotifier.value = TerminalPulseState(
      configuration: tab.terminalPulse,
      armed: pulse.armed,
      statusKnown: pulse.statusKnown,
      error: pulse.error,
    );
  }

  Future<void> _refreshTerminalPulseState(
    TerminalPtySession session, {
    required bool Function() isCurrent,
  }) async {
    if (session is! TerminalPulsePtySession || !session.supportsTerminalPulse) {
      if (isCurrent()) {
        _markTerminalPulseDisarmed();
      }
      return;
    }
    try {
      final state = await session.terminalPulseStatus();
      if (isCurrent()) {
        _terminalPulseNotifier.value = state;
      }
    } catch (error) {
      if (!isCurrent()) {
        return;
      }
      final current = _terminalPulseNotifier.value;
      _handleTerminalPulseChanged(
        TerminalPulseState(
          configuration: current.configuration,
          armed: current.armed,
          statusKnown: false,
          error: 'Terminal Pulse status could not be refreshed: $error',
        ),
      );
    }
  }

  void _markTerminalPulseDisarmed() {
    final current = _terminalPulseNotifier.value;
    if (current.statusKnown &&
        !current.armed &&
        current.configuration == _tab.terminalPulse) {
      return;
    }
    _terminalPulseNotifier.value = TerminalPulseState(
      configuration: _tab.terminalPulse,
      armed: false,
    );
  }

  void _handleTerminalPulseChanged(TerminalPulseState state) {
    _terminalPulseNotifier.value = state;
    if (state.error case final error?) {
      _notifyInteraction(error, error: true);
    }
    notifyListeners();
  }
}
