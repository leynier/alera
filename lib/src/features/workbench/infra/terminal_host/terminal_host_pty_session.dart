import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

final class TerminalHostPtySessionFactory implements TerminalPtySessionFactory {
  factory TerminalHostPtySessionFactory({required TerminalHostClient client}) {
    return TerminalHostPtySessionFactory._(client);
  }

  TerminalHostPtySessionFactory._(this._client);

  final TerminalHostClient _client;

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    return TerminalHostPtySession(
      client: _client,
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
    );
  }
}

final class TerminalHostPtySession implements TerminalPtySession {
  factory TerminalHostPtySession({
    required TerminalHostClient client,
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    return TerminalHostPtySession._(client, sessionId, workspaceId, tabId);
  }

  TerminalHostPtySession._(
    this._client,
    this._sessionId,
    this._workspaceId,
    this._tabId,
  );

  final TerminalHostClient _client;
  final String _sessionId;
  final String _workspaceId;
  final String _tabId;
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();

  StreamSubscription<TerminalHostEvent>? _hostSub;
  Future<TerminalHostAttachment>? _reattachFuture;
  Future<void>? _outputResyncFuture;
  GhosttyTerminalShellLaunch? _launch;
  String? _workingDirectory;
  int? _cols;
  int? _rows;
  bool _disposed = false;
  bool _started = false;
  bool _startedNewProcess = false;
  bool _outputPaused = false;
  Future<void>? _startFuture;
  Future<void> Function()? _onProcessCreated;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => _startedNewProcess;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
    Future<void> Function()? onProcessCreated,
  }) async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    if (_started) {
      return;
    }
    final existingStart = _startFuture;
    if (existingStart != null) {
      return existingStart;
    }
    _launch = launch;
    _workingDirectory = workingDirectory;
    _cols = cols;
    _rows = rows;
    _onProcessCreated = onProcessCreated;
    _hostSub ??= _client.eventsForSession(_sessionId).listen(_handleHostEvent);
    late final Future<void> startFuture;
    startFuture = _createOrAttach()
        .then((attachment) async {
          if (_disposed) {
            return;
          }
          _started = true;
          await _applyAttachment(attachment);
        })
        .whenComplete(() {
          if (identical(_startFuture, startFuture)) {
            _startFuture = null;
          }
        });
    _startFuture = startFuture;
    return startFuture;
  }

  Future<TerminalHostAttachment> _createOrAttach() {
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
    return _client.createOrAttach(
      sessionId: _sessionId,
      workspaceId: _workspaceId,
      tabId: _tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: cols,
      rows: rows,
    );
  }

  Future<void> _applyAttachment(TerminalHostAttachment attachment) async {
    _startedNewProcess = attachment.created;
    if (attachment.snapshot.isNotEmpty || attachment.created) {
      _events.add(
        TerminalPtySnapshotEvent(
          attachment.snapshot,
          resetInteractionModes: attachment.created || !attachment.running,
        ),
      );
    }
    if (!attachment.running) {
      final exitCode = attachment.exitCode;
      if (exitCode != null) {
        _events.add(TerminalPtyExitEvent(exitCode, notifyRuntime: false));
      }
    }
    if (attachment.created) {
      await _onProcessCreated?.call();
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    if (_disposed || !_started || bytes.isEmpty) {
      return false;
    }
    unawaited(_writeBytes(bytes).catchError(_emitHostError));
    return true;
  }

  @override
  Future<bool> writeBytesAndWait(List<int> bytes) async {
    if (_disposed || !_started || bytes.isEmpty) {
      return false;
    }
    try {
      await _client.write(sessionId: _sessionId, bytes: bytes);
    } catch (error) {
      if (!_isDefinitivelyNotAttached(error)) {
        rethrow;
      }
      final attachment = await _reattach();
      if (attachment.created) {
        return false;
      }
      await _client.write(sessionId: _sessionId, bytes: bytes);
    }
    return true;
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    if (_disposed) {
      return;
    }
    _cols = cols;
    _rows = rows;
    if (!_started) {
      return;
    }
    unawaited(_resize(cols: cols, rows: rows).catchError(_emitHostError));
  }

  Future<void> _writeBytes(List<int> bytes) async {
    try {
      await _client.write(sessionId: _sessionId, bytes: bytes);
    } catch (error) {
      if (!_isDefinitivelyNotAttached(error)) {
        rethrow;
      }
      await _reattach();
      await _client.write(sessionId: _sessionId, bytes: bytes);
    }
  }

  Future<void> _resize({required int cols, required int rows}) async {
    try {
      await _client.resize(sessionId: _sessionId, cols: cols, rows: rows);
    } catch (error) {
      if (!_shouldRecoverFromHostError(error)) {
        rethrow;
      }
      await _reattach();
      await _client.resize(sessionId: _sessionId, cols: cols, rows: rows);
    }
  }

  @override
  Future<void> setOutputPaused(bool paused) async {
    if (_disposed || !_started) {
      return;
    }
    _outputPaused = paused;
    try {
      final snapshot = await _client.setOutputPaused(
        sessionId: _sessionId,
        paused: paused,
      );
      _emitResumeSnapshot(paused: paused, snapshot: snapshot);
    } catch (error) {
      if (!_shouldRecoverFromHostError(error)) {
        _emitHostError(error);
        return;
      }
      try {
        await _reattach();
        final snapshot = await _client.setOutputPaused(
          sessionId: _sessionId,
          paused: paused,
        );
        _emitResumeSnapshot(paused: paused, snapshot: snapshot);
      } catch (retryError) {
        _emitHostError(retryError);
      }
    }
  }

  void _emitResumeSnapshot({
    required bool paused,
    required List<int> snapshot,
  }) {
    if (!_disposed && !paused) {
      _events.add(TerminalPtySnapshotEvent(Uint8List.fromList(snapshot)));
    }
  }

  Future<TerminalHostAttachment> _reattach() {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    final existing = _reattachFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<TerminalHostAttachment> next;
    next = _createOrAttach()
        .then((attachment) async {
          await _applyAttachment(attachment);
          return attachment;
        })
        .whenComplete(() {
          if (identical(_reattachFuture, next)) {
            _reattachFuture = null;
          }
        });
    _reattachFuture = next;
    return next;
  }

  bool _shouldRecoverFromHostError(Object error) {
    final message = _hostErrorMessage(error);
    return message.contains('Terminal session is not attached') ||
        message.contains('Terminal host connection closed');
  }

  bool _isDefinitivelyNotAttached(Object error) {
    return _hostErrorMessage(
      error,
    ).contains('Terminal session is not attached');
  }

  String _hostErrorMessage(Object error) {
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _started = false;
    unawaited(_hostSub?.cancel());
    _hostSub = null;
    unawaited(_client.detach(_sessionId).catchError((_) {}));
    unawaited(_events.close());
  }

  @override
  void terminate() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _started = false;
    unawaited(_hostSub?.cancel());
    _hostSub = null;
    _client.releaseSession(_sessionId);
    unawaited(_client.terminate(_sessionId).catchError((_) {}));
    unawaited(_events.close());
  }

  void _handleHostEvent(TerminalHostEvent event) {
    if (_disposed || event.sessionId != _sessionId) {
      return;
    }
    switch (event) {
      case TerminalHostOutputEvent(:final data):
        _events.add(TerminalPtyOutputEvent(data));
      case TerminalHostOutputTextEvent(:final text):
        _events.add(TerminalPtyOutputTextEvent(text));
      case TerminalHostOutputResyncRequiredEvent():
        _requestOutputResync();
      case TerminalHostExitEvent(:final exitCode):
        _events.add(TerminalPtyExitEvent(exitCode));
      case TerminalHostErrorEvent(:final error):
        if (!_isInputBackpressure(error)) {
          _events.add(TerminalPtyErrorEvent(error));
        }
      case TerminalHostDriverChangedEvent():
        // Driver presence is consumed by the workbench overlay, not the PTY
        // session stream.
        break;
    }
  }

  void _requestOutputResync() {
    if (_disposed || _outputPaused || _outputResyncFuture != null) {
      return;
    }
    late final Future<void> resync;
    resync = setOutputPaused(false).whenComplete(() {
      if (identical(_outputResyncFuture, resync)) {
        _outputResyncFuture = null;
      }
    });
    _outputResyncFuture = resync;
  }

  void _emitHostError(Object error) {
    if (!_disposed && !_events.isClosed && !_isInputBackpressure(error)) {
      _events.add(TerminalPtyErrorEvent(error));
    }
  }

  bool _isInputBackpressure(Object error) {
    return _hostErrorMessage(error).contains('terminal_input_backpressure');
  }
}
