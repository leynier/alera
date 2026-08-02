import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_session_controller.g.dart';

/// Raised into the session state when the desktop takes the viewport back
/// (`terminalDriverChanged` with a desktop driver); the tabs screen reacts by
/// leaving the terminal.
class DesktopReclaimedTerminal implements Exception {
  const DesktopReclaimedTerminal();

  @override
  String toString() => 'Desktop took back the terminal';
}

/// A live attachment to one terminal tab: the session handle, the scrollback
/// snapshot to replay, and the filtered output stream.
class TerminalTabSession {
  TerminalTabSession({
    required this.sessionId,
    required List<int> snapshot,
    required this.running,
    required this.output,
  }) : _snapshot = _TerminalSnapshotPayload(snapshot);

  final String sessionId;
  final bool running;
  final _TerminalSnapshotPayload _snapshot;

  /// Carries the full event, not just the bytes, so a resync answer that
  /// replaces the scrollback stays ordered against the live output around it.
  final Stream<MobileTerminalOutputEvent> output;

  /// Transfers the one-shot restore payload to the emulator and releases the
  /// controller's reference so rendered scrollback is not retained twice.
  List<int> takeSnapshot() => _snapshot.take();

  int get retainedSnapshotBytes => _snapshot.retainedBytes;
}

class _TerminalSnapshotPayload {
  _TerminalSnapshotPayload(this._bytes);

  List<int>? _bytes;

  int get retainedBytes => _bytes?.length ?? 0;

  List<int> take() {
    final value = _bytes;
    _bytes = null;
    return value ?? const <int>[];
  }
}

@riverpod
class TerminalSessionController extends _$TerminalSessionController {
  final Logger _logger = Logger('TerminalSessionController');
  MobileTerminalClient? _client;
  String? _sessionId;
  StreamSubscription<MobileRuntimeEvent>? _driverSub;
  bool _cleanupRegistered = false;
  bool _disposed = false;
  bool _recovering = false;
  bool _desktopReclaimed = false;
  MobileTerminalClient? _pendingRecoveryClient;
  int _cols = defaultTerminalCols;
  int _rows = defaultTerminalRows;

  bool get supportsRestart => _client?.supportsTerminalRestart ?? false;

  @override
  Future<TerminalTabSession> build(String hostId, String tabId) async {
    _registerCleanup();
    // Keep the auto-disposed connection provider alive without rebuilding this
    // controller on every reconnect. Recovery owns the loading phase so the UI
    // can distinguish reconnecting from a first start.
    ref.listen(terminalClientProvider(hostId), (_, next) {
      switch (next) {
        case AsyncLoading()
            when !_disposed && _client != null && !_desktopReclaimed:
          state = const AsyncLoading<TerminalTabSession>(progress: 0.25);
        case AsyncError(:final error, :final stackTrace)
            when !_disposed && !_recovering:
          state = AsyncError(error, stackTrace);
        case AsyncData(value: final client)
            when !_disposed &&
                _client != null &&
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
    return _bindSession(client, session);
  }

  void _handleLifecycleChange(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    if (_disposed ||
        next != AppLifecycleState.resumed ||
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
      _disposed = true;
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
    final sessionId = session.attachment.sessionId;
    if (_disposed) {
      _logger.warning(
        'discarding terminal session $sessionId after controller disposal',
      );
      unawaited(_detachQuietly(client, sessionId));
      return TerminalTabSession(
        sessionId: sessionId,
        snapshot: session.attachment.snapshot,
        running: session.attachment.running,
        output: client.terminalOutput.where(
          (event) => event.sessionId == sessionId,
        ),
      );
    }
    final previousClient = _client;
    final previousSessionId = _sessionId;
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
        if (_disposed ||
            event.name != 'terminalDriverChanged' ||
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
        if (_disposed) {
          _logger.warning(
            'terminal client reported an error after controller disposal',
            error,
            stackTrace,
          );
          return;
        }
        if (!_recovering && identical(_client, client)) {
          state = AsyncError(error, stackTrace);
        }
      },
      onDone: () {
        if (_disposed) {
          _logger.warning('terminal client ended after controller disposal');
          return;
        }
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
    if (_disposed) {
      _logger.warning('ignoring terminal recovery after controller disposal');
      return;
    }
    if (_recovering) {
      _pendingRecoveryClient = client;
      return;
    }
    _recovering = true;
    var nextClient = client;
    try {
      while (!_desktopReclaimed && !_disposed) {
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
          if (_disposed) {
            _logger.warning(
              'discarding terminal recovery session after controller disposal',
            );
            unawaited(_detachQuietly(nextClient, session.attachment.sessionId));
            break;
          }
          state = AsyncData(_bindSession(nextClient, session));
        } catch (error, stackTrace) {
          if (_disposed) {
            _logger.warning(
              'terminal recovery failed after controller disposal',
              error,
              stackTrace,
            );
            break;
          }
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
    if (_disposed) {
      _logger.warning('ignoring terminal reconnect after controller disposal');
      return;
    }
    _recovering = true;
    state = const AsyncLoading<TerminalTabSession>(progress: 0.25);
    try {
      ref.invalidate(hostConnectionControllerProvider(hostId));
      ref.invalidate(terminalClientProvider(hostId));
      final client = await ref.read(terminalClientProvider(hostId).future);
      if (_disposed) {
        _logger.warning(
          'discarding terminal reconnect client after controller disposal',
        );
        return;
      }
      final session = await client.attachTerminal(
        tabId,
        cols: _cols,
        rows: _rows,
      );
      if (_disposed) {
        _logger.warning(
          'discarding terminal reconnect session after controller disposal',
        );
        unawaited(_detachQuietly(client, session.attachment.sessionId));
        return;
      }
      state = AsyncData(_bindSession(client, session));
    } catch (error, stackTrace) {
      if (_disposed) {
        _logger.warning(
          'terminal reconnect failed after controller disposal',
          error,
          stackTrace,
        );
        return;
      }
      state = AsyncError(error, stackTrace);
    } finally {
      _recovering = false;
    }
  }

  Future<void> restartTerminal() async {
    if (_disposed) {
      _logger.warning('ignoring terminal restart after controller disposal');
      return;
    }
    final MobileTerminalClient client;
    if (_client case final currentClient?) {
      client = currentClient;
    } else {
      client = await ref.read(terminalClientProvider(hostId).future);
      if (_disposed) {
        _logger.warning(
          'discarding terminal restart client after controller disposal',
        );
        return;
      }
    }
    if (!client.supportsTerminalRestart) {
      state = AsyncError(
        UnsupportedError('The host does not support terminal restart.'),
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
      if (_disposed) {
        _logger.warning(
          'discarding terminal restart session after controller disposal',
        );
        unawaited(_detachQuietly(client, session.attachment.sessionId));
        return;
      }
      state = AsyncData(_bindSession(client, session));
    } catch (error, stackTrace) {
      if (_disposed) {
        _logger.warning(
          'terminal restart failed after controller disposal',
          error,
          stackTrace,
        );
        return;
      }
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

  /// Text from an explicit Paste action. It never submits the prompt, but it
  /// uses bracketed paste when control characters or a large payload require
  /// protection from the foreground line editor.
  Future<void> pasteText(String text) async {
    final session = await future;
    final client = await ref.read(terminalClientProvider(hostId).future);
    final delivery = TerminalComposeDelivery.forText(
      text,
      withEnter: false,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    await client.writeTerminal(
      session.sessionId,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
    );
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
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'could not detach terminal session $sessionId',
        error,
        stackTrace,
      );
    }
  }
}

/// Convenience for pre-resolving the session id of a tab without attaching.
String terminalSessionIdOf(WorkspaceTabSummary tab) => tab.terminalSessionId;
