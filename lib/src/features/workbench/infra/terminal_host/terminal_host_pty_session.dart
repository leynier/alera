import 'dart:async';

import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

part 'terminal_host_pty_session_pulse.dart';
part 'terminal_host_pty_session_lease.dart';
part 'terminal_host_pty_session_errors.dart';

final class TerminalHostPtySessionFactory implements TerminalPtySessionFactory {
  factory TerminalHostPtySessionFactory({required TerminalHostClient client}) {
    return TerminalHostPtySessionFactory._(client);
  }

  TerminalHostPtySessionFactory._(this._client);

  final TerminalHostClient _client;
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
    );
  }
}

final class TerminalHostPtySession
    with _TerminalPulsePtySessionSupport
    implements
        RecoverableTerminalPtySession,
        DeferredEnterTerminalPtySession,
        TerminalPulsePtySession {
  factory TerminalHostPtySession({
    required TerminalHostClient client,
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    return TerminalHostPtySession._(
      client,
      sessionId,
      workspaceId,
      tabId,
      null,
    );
  }

  TerminalHostPtySession._(
    this._client,
    this._sessionId,
    this._workspaceId,
    this._tabId,
    this._lease,
  );

  @override
  final TerminalHostClient _client;
  @override
  final String _sessionId;
  final String _workspaceId;
  final String _tabId;
  final _TerminalHostPtySessionLease? _lease;
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
  // Resize and output resync can both observe a lost attachment. Keep their
  // retries in one lane so no request races the createOrAttach response.
  Future<void> _attachmentOperations = Future<void>.value();
  Future<void> Function()? _onProcessCreated;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => _startedNewProcess;

  @override
  bool get supportsRestart => _client.supportsTerminalRestart;

  @override
  bool get supportsDeferredEnter => _client.supportsDeferredInput;

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
  bool writeBytesWithDeferredEnter(List<int> bytes) {
    if (_disposed || !_started) {
      return false;
    }
    unawaited(
      _writeBytes(bytes, deferredEnter: true).catchError(_emitHostError),
    );
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
    unawaited(
      _enqueueAttachmentOperation(
        () => _resize(cols: cols, rows: rows),
      ).catchError(_emitHostError),
    );
  }

  @override
  Future<void> refreshViewport(
    int cols,
    int rows,
    int cellWidthPx,
    int cellHeightPx,
  ) {
    if (_disposed || !_started) {
      return Future<void>.value();
    }
    _cols = cols;
    _rows = rows;
    final pulseCols = cols > 1 ? cols - 1 : cols + 1;
    return _enqueueAttachmentOperation<void>(() async {
      try {
        await _resize(cols: pulseCols, rows: rows);
      } finally {
        await _resize(cols: cols, rows: rows);
      }
    }).catchError(_emitHostError);
  }

  @override
  Future<T> _enqueueAttachmentOperation<T>(Future<T> Function() operation) {
    final previous = _attachmentOperations;
    final gate = Completer<void>();
    _attachmentOperations = gate.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        gate.complete();
      }
    });
  }

  Future<void> _writeBytes(
    List<int> bytes, {
    bool deferredEnter = false,
  }) async {
    await _withReattach(
      () => _client.write(
        sessionId: _sessionId,
        bytes: bytes,
        deferredEnter: deferredEnter,
      ),
      shouldRecover: _isDefinitivelyNotAttached,
    );
  }

  Future<void> _resize({required int cols, required int rows}) async {
    await _withReattach(
      () => _client.resize(sessionId: _sessionId, cols: cols, rows: rows),
      shouldRecover: _shouldRecoverFromHostError,
    );
  }

  @override
  Future<void> setOutputPaused(bool paused) {
    if (_disposed || !_started) {
      return Future<void>.value();
    }
    _outputPaused = paused;
    return _enqueueAttachmentOperation<void>(() async {
      try {
        final resume = await _withReattach(
          () => _client.setOutputPaused(sessionId: _sessionId, paused: paused),
          shouldRecover: _shouldRecoverFromHostError,
        );
        _emitResume(paused: paused, resume: resume);
      } catch (error) {
        _emitHostError(error);
      }
    });
  }

  @override
  Future<T> _withReattach<T>(
    Future<T> Function() operation, {
    required bool Function(Object error) shouldRecover,
  }) async {
    try {
      return await operation();
    } catch (error) {
      if (!shouldRecover(error)) {
        rethrow;
      }
      await _reattach();
      return operation();
    }
  }

  void _emitResume({required bool paused, required TerminalHostResume resume}) {
    if (_disposed || paused || resume.isDelta) {
      // A delta resume needs nothing here: the host already pushed the missed
      // bytes on the output lane, ahead of whatever comes next.
      return;
    }
    _events.add(
      TerminalPtySnapshotEvent(
        resume.snapshot,
        resetInteractionModes: resume.resetInteractionModes,
      ),
    );
  }

  @override
  Future<void> reconnect() =>
      _enqueueAttachmentOperation<void>(() => _reattach().then((_) {}));

  @override
  Future<void> restartProcess() async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
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
    final attachment = await _client.restart(
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

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _started = false;
    unawaited(_hostSub?.cancel());
    _hostSub = null;
    if (_lease?.release() ?? true) {
      unawaited(_client.detach(_sessionId).catchError((_) {}));
    }
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
    _lease?.terminate();
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
      case TerminalHostPulseChangedEvent(:final state):
        _events.add(TerminalPtyPulseChangedEvent(state));
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
}
