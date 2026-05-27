import 'dart:async';

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
  Future<void>? _reattachFuture;
  GhosttyTerminalShellLaunch? _launch;
  String? _workingDirectory;
  int? _cols;
  int? _rows;
  bool _disposed = false;
  bool _startedNewProcess = false;

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
  }) async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    _launch = launch;
    _workingDirectory = workingDirectory;
    _cols = cols;
    _rows = rows;
    _hostSub ??= _client.events.listen(_handleHostEvent);
    final attachment = await _createOrAttach();
    _applyAttachment(attachment);
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

  void _applyAttachment(TerminalHostAttachment attachment) {
    _startedNewProcess = attachment.created;
    if (attachment.snapshot.isNotEmpty) {
      _events.add(TerminalPtyOutputEvent(attachment.snapshot));
    }
    if (!attachment.running) {
      final exitCode = attachment.exitCode;
      if (exitCode != null) {
        _events.add(TerminalPtyExitEvent(exitCode, notifyRuntime: false));
      }
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    if (_disposed || bytes.isEmpty) {
      return false;
    }
    unawaited(_writeBytes(bytes).catchError(_emitHostError));
    return true;
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    if (_disposed) {
      return;
    }
    _cols = cols;
    _rows = rows;
    unawaited(_resize(cols: cols, rows: rows).catchError(_emitHostError));
  }

  Future<void> _writeBytes(List<int> bytes) async {
    try {
      await _client.write(sessionId: _sessionId, bytes: bytes);
    } catch (error) {
      if (!_shouldRecoverFromHostError(error)) {
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

  Future<void> _reattach() {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    final existing = _reattachFuture;
    if (existing != null) {
      return existing;
    }
    late final Future<void> next;
    next = _createOrAttach().then(_applyAttachment).whenComplete(() {
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
    unawaited(_hostSub?.cancel());
    _hostSub = null;
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
      case TerminalHostExitEvent(:final exitCode):
        _events.add(TerminalPtyExitEvent(exitCode));
      case TerminalHostErrorEvent(:final error):
        _events.add(TerminalPtyErrorEvent(error));
    }
  }

  void _emitHostError(Object error) {
    if (!_disposed && !_events.isClosed) {
      _events.add(TerminalPtyErrorEvent(error));
    }
  }
}
