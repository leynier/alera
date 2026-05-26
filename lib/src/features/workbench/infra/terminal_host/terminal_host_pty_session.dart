// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

final class TerminalHostPtySessionFactory implements TerminalPtySessionFactory {
  const TerminalHostPtySessionFactory({required TerminalHostClient client})
    : _client = client;

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
  TerminalHostPtySession({
    required TerminalHostClient client,
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) : _client = client,
       _sessionId = sessionId,
       _workspaceId = workspaceId,
       _tabId = tabId;

  final TerminalHostClient _client;
  final String _sessionId;
  final String _workspaceId;
  final String _tabId;
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();

  StreamSubscription<TerminalHostEvent>? _hostSub;
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
    _hostSub ??= _client.events.listen(_handleHostEvent);
    final attachment = await _client.createOrAttach(
      sessionId: _sessionId,
      workspaceId: _workspaceId,
      tabId: _tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: cols,
      rows: rows,
    );
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
    unawaited(
      _client
          .write(sessionId: _sessionId, bytes: bytes)
          .catchError(_emitHostError),
    );
    return true;
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    if (_disposed) {
      return;
    }
    unawaited(
      _client
          .resize(sessionId: _sessionId, cols: cols, rows: rows)
          .catchError(_emitHostError),
    );
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
