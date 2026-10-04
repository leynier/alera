part of 'terminal_host_pty_session.dart';

/// Decides whether a tab attaches read-only, which is only ever true for an
/// automation-owned tab nobody took over.
typedef TerminalObservedTabResolver = bool Function(
  String workspaceId,
  String tabId,
);

final class TerminalHostPtySessionFactory._(
  final TerminalHostClient _client,
  final TerminalObservedTabResolver? _observeTab,
) implements TerminalPtySessionFactory {
  factory({
    required TerminalHostClient client,
    TerminalObservedTabResolver? observeTab,
  }) {
    return TerminalHostPtySessionFactory._(client, observeTab);
  }

  final _TerminalHostPtySessionLeases _leases = _TerminalHostPtySessionLeases();

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    return TerminalHostPtySession._(
      _client,
      sessionId,
      workspaceId,
      tabId,
      _leases.acquire(sessionId),
      _observeTab,
    );
  }
}
