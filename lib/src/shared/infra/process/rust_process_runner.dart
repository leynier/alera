import 'dart:async';
import 'dart:io';

import 'package:alera/src/rust/api/process.dart' as rust;
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// [ProcessRunner] backed by the Rust crate through flutter_rust_bridge. This is
/// the only place that knows about the generated bridge types.
///
/// Spawning lives in Rust because `dart:io` cannot pass `CREATE_NO_WINDOW`: the
/// Windows runner is a GUI-subsystem binary with no console, so every console
/// child it starts would get a console window of its own and flash on screen.
/// Failures are translated back into [ProcessException] so call sites keep
/// seeing what `Process.run` used to throw.
class const RustProcessRunner() implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final result = await rust.processRun(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
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
      stdinWrite: (data) =>
          _enqueueStdin((id) => rust.processWriteStdin(id: id, data: data)),
      stdinClose: () => _enqueueStdin((id) => rust.processCloseStdin(id: id)),
      stdout: _stdout.stream,
      stderr: _stderr.stream,
      pid: pid,
      exitCode: _exitCode.future,
      kill: ([signal]) {
        final id = _sessionId;
        if (id == null) {
          return false;
        }
        unawaited(rust.processKill(id: id));
        return true;
      },
    );
  }

  void _enqueueStdin(Future<void> Function(int id) call) {
    final id = _sessionId;
    if (id == null) {
      return;
    }
    _stdinWrites = _stdinWrites.then((_) => call(id)).catchError((Object _) {});
  }

  void _finish(int exitCode) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(exitCode);
    }
    _close();
  }

  void _fail(String message) {
    final failure = ProcessException(_executable, _arguments, message);
    if (!_started.isCompleted) {
      _started.completeError(failure);
    }
    if (!_exitCode.isCompleted) {
      _exitCode.completeError(failure);
    }
    _close();
  }

  void _close() {
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }
}
