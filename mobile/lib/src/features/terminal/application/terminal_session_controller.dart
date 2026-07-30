import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_session_controller.g.dart';

/// Raised into the session state when the desktop takes the viewport back
/// (`terminalDriverChanged` with a desktop driver); the tabs screen reacts by
/// leaving the terminal.
class DesktopReclaimedTerminal implements Exception {
  const DesktopReclaimedTerminal();

  @override
  String toString() => 'Desktop Took Back The Terminal';
}

/// A live attachment to one terminal tab: the session handle, the scrollback
/// snapshot to replay, and the filtered output stream.
class TerminalTabSession {
  const TerminalTabSession({
    required this.sessionId,
    required this.snapshot,
    required this.running,
    required this.output,
  });

  final String sessionId;
  final List<int> snapshot;
  final bool running;

  /// Carries the full event, not just the bytes, so a resync answer that
  /// replaces the scrollback stays ordered against the live output around it.
  final Stream<MobileTerminalOutputEvent> output;
}

@riverpod
class TerminalSessionController extends _$TerminalSessionController {
  MobileTerminalClient? _client;
  String? _sessionId;
  StreamSubscription<MobileRuntimeEvent>? _driverSub;
  bool _cleanupRegistered = false;
  bool _recovering = false;
  bool _desktopReclaimed = false;
  MobileTerminalClient? _pendingRecoveryClient;
  int _cols = defaultTerminalCols;
  int _rows = defaultTerminalRows;

  bool get supportsRestart => _client?.supportsTerminalRestart ?? false;

  @override
  Future<TerminalTabSession> build(String hostId, String tabId) async {
    // Keep the auto-disposed connection provider alive without rebuilding this
    // controller on every reconnect. Recovery owns the loading phase so the UI
    // can distinguish reconnecting from a first start.
    ref.listen(terminalClientProvider(hostId), (_, next) {
      switch (next) {
        case AsyncLoading() when _client != null && !_desktopReclaimed:
          state = const AsyncLoading<TerminalTabSession>(progress: 0.25);
        case AsyncError(:final error, :final stackTrace) when !_recovering:
          state = AsyncError(error, stackTrace);
        case AsyncData(value: final client)
            when _client != null &&
                !identical(_client, client) &&
                !_desktopReclaimed:
          unawaited(_recoverWithClient(client));
        default:
          break;
      }
    });
    ref.listen(appLifecycleControllerProvider, _handleLifecycleChange);
    final client = await ref.read(terminalClientProvider(hostId).future);
    // The runtime restarts exited sessions under the same handle during
    // attach, so a single attach always yields a usable session.
    final session = await client.attachTerminal(tabId);
    _registerCleanup();
    return _bindSession(client, session);
  }

  void _handleLifecycleChange(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    if (next != AppLifecycleState.resumed ||
        previous == AppLifecycleState.resumed ||
        _desktopReclaimed) {
      return;
    }
    final client = _client;
    if (client != null) {
      unawaited(_recoverWithClient(client, showStartingState: true));
    }
  }

  void _registerCleanup() {
    if (_cleanupRegistered) {
      return;
    }
    _cleanupRegistered = true;
    ref.onDispose(() {
      unawaited(_driverSub?.cancel());
      final client = _client;
      final sessionId = _sessionId;
      if (client != null && sessionId != null) {
        unawaited(_detachQuietly(client, sessionId));
      }
    });
  }

  TerminalTabSession _bindSession(
    MobileTerminalClient client,
    MobileTerminalSession session,
  ) {
    final previousClient = _client;
    final previousSessionId = _sessionId;
    final sessionId = session.attachment.sessionId;
    unawaited(_driverSub?.cancel());
    if (previousClient != null &&
        previousSessionId != null &&
        (!identical(previousClient, client) ||
            previousSessionId != sessionId)) {
      unawaited(_detachQuietly(previousClient, previousSessionId));
    }
    _client = client;
    _sessionId = sessionId;
    _driverSub = client.events.listen(
      (event) {
        if (event.name != 'terminalDriverChanged' ||
            event.payload['sessionId'] != sessionId) {
          return;
        }
        final driver = asJsonMap(event.payload['driver']);
        if (driver['kind'] == 'desktop') {
          _desktopReclaimed = true;
          state = AsyncError(
            const DesktopReclaimedTerminal(),
            StackTrace.current,
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_recovering && identical(_client, client)) {
          state = AsyncError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_recovering && identical(_client, client)) {
          state = AsyncError(const RuntimeConnectionLost(), StackTrace.current);
        }
      },
    );
    return TerminalTabSession(
      sessionId: sessionId,
      snapshot: session.attachment.snapshot,
      running: session.attachment.running,
      output: client.terminalOutput.where(
        (event) => event.sessionId == sessionId,
      ),
    );
  }

  Future<void> _recoverWithClient(
    MobileTerminalClient client, {
    bool showStartingState = false,
  }) async {
    if (_recovering) {
      _pendingRecoveryClient = client;
      return;
    }
    _recovering = true;
    var nextClient = client;
    try {
      while (!_desktopReclaimed) {
        _pendingRecoveryClient = null;
        state = showStartingState
            ? const AsyncLoading<TerminalTabSession>()
            : const AsyncLoading<TerminalTabSession>(progress: 0.25);
        showStartingState = false;
        try {
          final session = await nextClient.attachTerminal(
            tabId,
            cols: _cols,
            rows: _rows,
          );
          state = AsyncData(_bindSession(nextClient, session));
        } catch (error, stackTrace) {
          state = AsyncError(error, stackTrace);
        }
        final pendingClient = _pendingRecoveryClient;
        if (pendingClient == null || identical(pendingClient, nextClient)) {
          break;
        }
        nextClient = pendingClient;
      }
    } finally {
      _pendingRecoveryClient = null;
      _recovering = false;
    }
  }

  Future<void> reconnect() async {
    _recovering = true;
    state = const AsyncLoading<TerminalTabSession>(progress: 0.25);
    try {
      ref.invalidate(hostConnectionControllerProvider(hostId));
      ref.invalidate(terminalClientProvider(hostId));
      final client = await ref.read(terminalClientProvider(hostId).future);
      final session = await client.attachTerminal(
        tabId,
        cols: _cols,
        rows: _rows,
      );
      state = AsyncData(_bindSession(client, session));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    } finally {
      _recovering = false;
    }
  }

  Future<void> restartTerminal() async {
    final MobileTerminalClient client;
    if (_client case final currentClient?) {
      client = currentClient;
    } else {
      client = await ref.read(terminalClientProvider(hostId).future);
    }
    if (!client.supportsTerminalRestart) {
      state = AsyncError(
        UnsupportedError('The Host Does Not Support Terminal Restart.'),
        StackTrace.current,
      );
      return;
    }
    state = const AsyncLoading<TerminalTabSession>(progress: 0.75);
    try {
      final session = await client.restartTerminal(
        tabId,
        sessionId: _sessionId,
        cols: _cols,
        rows: _rows,
      );
      state = AsyncData(_bindSession(client, session));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Raw keystrokes: the accessory bar and direct mode. These must never be
  /// pasted or deferred, since each one is already a single key.
  Future<void> write(List<int> bytes) async {
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    await client.writeTerminal(session.sessionId, bytes);
  }

  /// Compose-mode send. The prompt and its Enter become separate PTY writes
  /// when the host supports it, because an agent TUI reads a CR arriving inside
  /// an input burst as a literal newline instead of a submit.
  Future<void> sendComposedText(String text, {required bool withEnter}) async {
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    final delivery = TerminalComposeDelivery.forText(
      text,
      withEnter: withEnter,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    await client.writeTerminal(
      session.sessionId,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
      deferredEnter: delivery.deferredEnter,
    );
  }

  Future<void> resize(int cols, int rows) async {
    if (cols <= 0 || rows <= 0) {
      return;
    }
    _cols = cols;
    _rows = rows;
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    await client.resizeTerminal(session.sessionId, cols, rows);
  }

  Future<void> _detachQuietly(
    MobileTerminalClient client,
    String sessionId,
  ) async {
    try {
      await client.detachTerminal(sessionId);
    } on Object {
      // The socket may already be gone; leaving is best-effort.
    }
  }
}

/// Convenience for pre-resolving the session id of a tab without attaching.
String terminalSessionIdOf(WorkspaceTabSummary tab) => tab.terminalSessionId;
