import 'dart:async';
import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/process/process_output.dart';
import 'package:alera/src/rust/api/process.dart' as rust;

const _stdinChunkBytes = 256 * 1024;
const _stdinRetryDelays = <Duration>[
  Duration(milliseconds: 2),
  Duration(milliseconds: 5),
  Duration(milliseconds: 10),
  Duration(milliseconds: 20),
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
];
const _stdinMaxRetryAttempts = 100;
const _stdinMaxQueuedBytes = 8 * 1024 * 1024;
const _stdinMaxQueuedWrites = 64;

/// [ProcessRunner] backed by the Rust crate through flutter_rust_bridge. This is
/// the only place that knows about the generated bridge types.
///
/// Spawning lives in Rust because `dart:io` cannot pass `CREATE_NO_WINDOW`: the
/// Windows runner is a GUI-subsystem binary with no console, so every console
/// child it starts would get a console window of its own and flash on screen.
/// Failures are translated back into [ProcessException] so call sites keep
/// seeing what `Process.run` used to throw.
class const RustProcessRunner()
    implements ProcessRunner, ProcessRunnerWithOutputBudget {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return runWithOutputBudget(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      maxOutputBytes: processRunDefaultMaxOutputBytes,
    );
  }

  @override
  Future<ProcessRunOutput> runWithOutputBudget(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required int maxOutputBytes,
    Duration? timeout,
  }) async {
    try {
      final result = await rust.processRunWithOutputLimit(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        maxOutputBytes: maxOutputBytes,
        timeoutMillis: timeout?.inMilliseconds,
      );
      return ProcessRunOutput(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    } on Object catch (error) {
      throw ProcessException(executable, arguments, '$error');
    }
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    final session = _ProcessSession(executable, arguments);
    session.listen(
      rust.processStart(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
      ),
    );
    return session.started;
  }
}

/// Demultiplexes the single event stream the bridge exposes back into the
/// stdout, stderr and exit-code surfaces [StartedProcess] is made of.
class _ProcessSession(final String _executable, final List<String> _arguments) {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final Completer<StartedProcess> _started = Completer<StartedProcess>();

  /// Bridge calls are serialized behind this chain so a write can never be
  /// overtaken by the close that follows it.
  Future<void> _stdinWrites = Future<void>.value();
  int? _sessionId;
  bool _stdinWritable = true;
  bool _stdinClosed = false;
  bool _closed = false;
  int _pendingStdinBytes = 0;
  int _pendingStdinWrites = 0;

  Future<StartedProcess> get started => _started.future;

  void listen(Stream<rust.ProcessEvent> events) {
    events.listen(
      _onEvent,
      onError: (Object error) => _fail('$error'),
      onDone: () => _fail('$_executable ended without reporting an exit code'),
      cancelOnError: true,
    );
  }

  void _onEvent(rust.ProcessEvent event) {
    if (_closed) {
      return;
    }
    switch (event.kind) {
      case rust.ProcessEventKind.started:
        _sessionId = event.sessionId.toInt();
        _started.complete(_startedProcess(event.pid));
      case rust.ProcessEventKind.stdout:
        _stdout.add(event.data);
      case rust.ProcessEventKind.stderr:
        _stderr.add(event.data);
      case rust.ProcessEventKind.exit:
        _finish(event.exitCode);
      case rust.ProcessEventKind.failure:
        _fail(event.message);
    }
  }

  StartedProcess _startedProcess(int pid) {
    return StartedProcess(
      stdinWrite: _enqueueStdinWrite,
      stdinClose: () {
        _stdinClosed = true;
        _enqueueStdin((id) => rust.processCloseStdin(id: id));
      },
      stdout: _stdout.stream,
      stderr: _stderr.stream,
      pid: pid,
      exitCode: _exitCode.future,
      kill: ([signal]) {
        final id = _sessionId;
        if (id == null) {
          return false;
        }
        _stdinWritable = false;
        _killSession(id);
        return true;
      },
    );
  }

  void _enqueueStdinWrite(List<int> data) {
    if (_stdinClosed) {
      _fail('stdin is already closed.');
      return;
    }
    if (data.length > _stdinMaxQueuedBytes ||
        _pendingStdinWrites >= _stdinMaxQueuedWrites ||
        data.length > _stdinMaxQueuedBytes - _pendingStdinBytes) {
      _fail(
        'stdin input exceeded the bounded process queue '
        '($_stdinMaxQueuedBytes bytes).',
      );
      return;
    }
    _pendingStdinBytes += data.length;
    _pendingStdinWrites += 1;
    _enqueueStdin(
      (id) => _writeStdinChunks(id, data),
      onDone: () {
        _pendingStdinBytes -= data.length;
        _pendingStdinWrites -= 1;
      },
    );
  }

  Future<void> _writeStdinChunks(int id, List<int> data) async {
    for (var offset = 0; offset < data.length; offset += _stdinChunkBytes) {
      final end = offset + _stdinChunkBytes < data.length
          ? offset + _stdinChunkBytes
          : data.length;
      final chunk = data.length <= _stdinChunkBytes
          ? data
          : data.sublist(offset, end);
      var retryAttempt = 0;
      while (_stdinWritable) {
        final accepted = await _writeStdinChunk(id, chunk);
        if (accepted) {
          break;
        }
        if (!_stdinWritable) {
          return;
        }
        if (retryAttempt >= _stdinMaxRetryAttempts) {
          _fail(
            'stdin remained backpressured after '
            '$_stdinMaxRetryAttempts retries.',
          );
          return;
        }
        final delayIndex = retryAttempt < _stdinRetryDelays.length
            ? retryAttempt
            : _stdinRetryDelays.length - 1;
        await Future.pause(_stdinRetryDelays[delayIndex]);
        retryAttempt += 1;
      }
      if (!_stdinWritable) {
        return;
      }
    }
  }

  Future<bool> _writeStdinChunk(int id, List<int> chunk) async {
    try {
      return await rust.processWriteStdin(id: id, data: chunk);
    } on Object catch (error) {
      if (_stdinWritable && !_exitCode.isCompleted) {
        _fail('failed to write stdin: $error');
      }
      return false;
    }
  }

  void _killSession(int id) {
    unawaited(rust.processKill(id: id).catchError((_) => false));
  }

  void _enqueueStdin(
    Future<void> Function(int id) call, {
    void Function()? onDone,
  }) {
    final id = _sessionId;
    if (id == null) {
      onDone?.call();
      return;
    }
    _stdinWrites = _stdinWrites
        .then((_) async {
          try {
            if (_stdinWritable) {
              await call(id);
            }
          } finally {
            onDone?.call();
          }
        })
        .catchError((Object _) {});
  }

  void _finish(int exitCode) {
    _stdinWritable = false;
    if (!_exitCode.isCompleted) {
      _exitCode.complete(exitCode);
    }
    _close();
  }

  void _fail(String message) {
    if (_closed) {
      return;
    }
    final id = _sessionId;
    _stdinWritable = false;
    final failure = ProcessException(_executable, _arguments, message);
    if (!_started.isCompleted) {
      _started.completeError(failure);
    }
    if (!_exitCode.isCompleted) {
      _exitCode.completeError(failure);
    }
    if (id != null) {
      _killSession(id);
    }
    _close();
  }

  void _close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }
}
