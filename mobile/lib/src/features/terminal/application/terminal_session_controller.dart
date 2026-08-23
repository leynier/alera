import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_session_controller.g.dart';

const Duration _foregroundProbeTimeout = Duration(seconds: 8);

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
  Completer<void>? _recoveryCompletion;
  MobileTerminalClient? _pendingRecoveryClient;
  // Null until the terminal has been laid out. Claiming a viewport resizes the
  // live PTY, so a guess here is a resize to a size nobody is looking at.
  int? _cols;
  int? _rows;

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
    final session = await client.attachTerminal(
      tabId,
      cols: _cols,
      rows: _rows,
    );
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
      unawaited(_recoverIfConnectionLost(client));
    }
  }

  /// Returning to the foreground does not, by itself, mean the session is
  /// gone. Re-attaching regardless takes the tab through its loading state,
  /// which disposes the compose bar along with whatever it was waiting on: a
  /// path picked from the gallery landed on a dead controller and vanished,
  /// and the terminal appeared to restart every time the picker closed. One
  /// round trip separates the two cases, and a connection that answers is
  /// still delivering output, so nothing needs re-attaching.
  Future<void> _recoverIfConnectionLost(MobileTerminalClient client) async {
    try {
      await client.probeConnection().timeout(_foregroundProbeTimeout);
      return;
    } on Object catch (error, stackTrace) {
      if (_disposed || !identical(_client, client)) {
        return;
      }
      _logger.warning(
        'foreground probe failed for terminal $tabId; reattaching',
        error,
        stackTrace,
      );
    }
    if (_disposed || _desktopReclaimed || !identical(_client, client)) {
      return;
    }
    await _recoverWithClient(client, showStartingState: true);
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
        snapshotCols: session.attachment.snapshotCols,
        snapshotRows: session.attachment.snapshotRows,
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
      snapshotCols: session.attachment.snapshotCols,
      snapshotRows: session.attachment.snapshotRows,
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
      return _recoveryCompletion?.future ?? Future<void>.value();
    }
    _recovering = true;
    final completion = Completer<void>();
    _recoveryCompletion = completion;
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
      _recoveryCompletion = null;
      completion.complete();
    }
  }

  Future<void> reconnect() async {
    if (_disposed) {
      _logger.warning('ignoring terminal reconnect after controller disposal');
      return;
    }
    state = const AsyncLoading<TerminalTabSession>(progress: 0.25);
    final previousClient = _client;
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
      final activeRecovery = _recoveryCompletion;
      if (activeRecovery != null) {
        await activeRecovery.future;
      } else if (identical(previousClient, client) ||
          !identical(_client, client)) {
        await _recoverWithClient(client);
      }
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
      // A restart mints a new PTY, so unlike attach it always needs a size;
      // an unmeasured terminal has nothing better than the default to give.
      final session = await client.restartTerminal(
        tabId,
        sessionId: _sessionId,
        cols: _cols ?? defaultTerminalCols,
        rows: _rows ?? defaultTerminalRows,
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

  /// Raw accessory/direct keys are never pasted or deferred.
  Future<void> write(List<int> bytes) => _runAttachedOperation(
    (client, sessionId) => client.writeTerminal(sessionId, bytes),
  );

  /// Explicit paste never submits and brackets only when the text needs it.
  Future<void> pasteText(String text) => _runAttachedOperation((client, id) {
    final delivery = TerminalComposeDelivery.forText(
      text,
      withEnter: false,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    return client.writeTerminal(
      id,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
    );
  });

  /// Compose send separates prompt bytes from Enter when the host supports it.
  Future<void> sendComposedText(String text, {required bool withEnter}) =>
      _runAttachedOperation((client, id) {
        final delivery = TerminalComposeDelivery.forText(
          text,
          withEnter: withEnter,
          hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
        );
        return client.writeTerminal(
          id,
          delivery.bytes,
          bracketedPaste: delivery.bracketedPaste,
          deferredEnter: delivery.deferredEnter,
        );
      });

  Future<void> resize(int cols, int rows) async {
    if (cols <= 0 || rows <= 0) {
      return;
    }
    _cols = cols;
    _rows = rows;
    await _runAttachedOperation(
      (client, sessionId) => client.resizeTerminal(sessionId, cols, rows),
    );
  }

  Future<void> _runAttachedOperation(
    Future<void> Function(MobileTerminalClient client, String sessionId)
    operation,
  ) async {
    final session = await future;
    if (_disposed) {
      return;
    }
    final client = _client;
    if (client == null) {
      throw StateError('Terminal session has no bound client.');
    }
    try {
      await operation(client, session.sessionId);
      return;
    } on Object catch (error) {
      if (!_isSessionNotAttached(error)) {
        rethrow;
      }
      await (_recoveryCompletion?.future ?? _recoverWithClient(client));
      if (_disposed) {
        return;
      }
      if (state case AsyncError(:final error, :final stackTrace)) {
        _logger.warning(
          'terminal late attach recovery failed',
          error,
          stackTrace,
        );
        return;
      }
      final recovered = switch (state) {
        AsyncData(value: final value) => value,
        _ => null,
      };
      final recoveredClient = _client;
      if (recovered == null || recoveredClient == null) {
        return;
      }
      try {
        await operation(recoveredClient, recovered.sessionId);
      } on Object catch (retryError, retryStackTrace) {
        if (!_isSessionNotAttached(retryError)) {
          rethrow;
        }
        if (_disposed) {
          _logger.warning('terminal retry failed after controller disposal');
          return;
        }
        _logger.warning(
          'terminal session remained unavailable after reattach',
          retryError,
          retryStackTrace,
        );
        state = AsyncError(retryError, retryStackTrace);
      }
    }
  }

  bool _isSessionNotAttached(Object error) =>
      (error is StateError ? error.message : error.toString()).contains(
        'Terminal session is not attached',
      );

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
