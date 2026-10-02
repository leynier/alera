import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/updater_process_adapter.dart';
import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:desktop_updater/desktop_updater.dart' as updater;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeProcessRunner runner;
  late _FakeStartedProcess process;

  setUp(() {
    process = _FakeStartedProcess();
    runner = _FakeProcessRunner(process);
  });

  tearDown(() async {
    await process.dispose();
  });

  test(
    'forwards the command, closes stdin, and decodes split output',
    () async {
      final adapter = UpdaterProcessAdapter(
        processRunner: runner,
        timeout: const Duration(seconds: 1),
      );
      final run = adapter.run('/usr/bin/plutil', <String>['-convert', 'xml']);
      await runner.started;

      final outputBytes = utf8.encode('café\n');
      final split = outputBytes.indexOf(0xC3) + 1;
      process.stdoutController.add(outputBytes.sublist(0, split));
      process.stdoutController.add(outputBytes.sublist(split));
      process.stderrController.add(<int>[0xFF]);
      await process.closeOutput();
      process.completeExit();

      final result = await run;
      expect(runner.executable, '/usr/bin/plutil');
      expect(runner.arguments, <String>['-convert', 'xml']);
      expect(process.stdinCloseCalls, 1);
      expect(result.pid, process.pid);
      expect(result.exitCode, 0);
      expect(result.stdout, 'café\n');
      expect(result.stderr, '�');
    },
  );

  test(
    'bounds combined stdout and stderr output and kills the process',
    () async {
      final adapter = UpdaterProcessAdapter(
        processRunner: runner,
        maxOutputBytes: 5,
        timeout: const Duration(seconds: 1),
      );
      final outcomeFuture = _capture(
        adapter.run('/bin/tool', const <String>[]),
      );
      await runner.started;

      process.stdoutController.add(<int>[1, 2, 3]);
      process.stderrController.add(<int>[4, 5, 6]);
      await process.killedSignal.future;
      var outcomeCompleted = false;
      unawaited(outcomeFuture.then<void>((_) => outcomeCompleted = true));
      await Future.pause(Duration.zero);
      expect(outcomeCompleted, isFalse);

      process.completeExit(137);
      final outcome = await outcomeFuture;
      expect(outcome.error, isA<ProcessException>());
      expect(outcome.error.toString(), contains('exceeds 5 bytes'));
      expect(process.killCalls, 1);
    },
  );

  test(
    'times out, kills, and waits for the child to exit before returning',
    () async {
      final adapter = UpdaterProcessAdapter(
        processRunner: runner,
        timeout: const Duration(milliseconds: 10),
      );
      final outcomeFuture = _capture(
        adapter.run('/bin/hung-tool', const <String>[]),
      );
      await runner.started;
      await process.killedSignal.future.timeout(const Duration(seconds: 1));

      var outcomeCompleted = false;
      unawaited(outcomeFuture.then<void>((_) => outcomeCompleted = true));
      await Future.pause(Duration.zero);
      expect(outcomeCompleted, isFalse);

      process.completeExit(143);
      final outcome = await outcomeFuture;
      expect(outcome.error, isA<TimeoutException>());
      expect(process.killed, isTrue);
    },
  );

  test('rejects cancellation before spawning', () async {
    final token = updater.UpdateCancellationToken()..cancel();
    final adapter = UpdaterProcessAdapter(
      processRunner: runner,
      timeout: const Duration(seconds: 1),
    );

    await expectLater(
      adapter.run('/bin/tool', const <String>[], cancellationToken: token),
      throwsA(isA<updater.UpdateCancelledException>()),
    );
    expect(runner.startCalls, 0);
  });

  test('cancels an active process and waits for its exit', () async {
    final token = updater.UpdateCancellationToken();
    final adapter = UpdaterProcessAdapter(
      processRunner: runner,
      timeout: const Duration(seconds: 1),
    );
    final outcomeFuture = _capture(
      adapter.run('/bin/long-tool', const <String>[], cancellationToken: token),
    );
    await runner.started;

    token.cancel();
    await process.killedSignal.future;
    var outcomeCompleted = false;
    unawaited(outcomeFuture.then<void>((_) => outcomeCompleted = true));
    await Future.pause(Duration.zero);
    expect(outcomeCompleted, isFalse);

    process.completeExit(143);
    final outcome = await outcomeFuture;
    expect(outcome.error, isA<updater.UpdateCancelledException>());
    expect(process.killed, isTrue);
  });

  test('preserves a stdin close failure and reaps the child', () async {
    final stdinError = StateError('stdin close failed');
    process.stdinCloseError = stdinError;
    final adapter = UpdaterProcessAdapter(
      processRunner: runner,
      timeout: const Duration(seconds: 1),
    );
    final outcomeFuture = _capture(adapter.run('/bin/tool', const <String>[]));
    await runner.started;
    await process.killedSignal.future;
    process.completeExit(1);

    final outcome = await outcomeFuture;
    expect(outcome.error, same(stdinError));
    expect(process.killCalls, 1);
  });

  test(
    'preserves a stream failure when killing the child also fails',
    () async {
      final streamError = StateError('stdout failed');
      process.killError = StateError('kill failed');
      final adapter = UpdaterProcessAdapter(
        processRunner: runner,
        timeout: const Duration(seconds: 1),
      );
      final outcomeFuture = _capture(
        adapter.run('/bin/tool', const <String>[]),
      );
      await runner.started;
      process.stdoutController.addError(streamError);
      await process.killedSignal.future;
      process.completeExit(1);

      final outcome = await outcomeFuture;
      expect(outcome.error, same(streamError));
      expect(process.killCalls, 1);
    },
  );

  test('applies POSIX file modes without starting a process', () async {
    if (Platform.isWindows) {
      return;
    }
    final directory = await Directory.systemTemp.createTemp(
      'alera-updater-mode',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/staged-file')
      ..writeAsStringSync('data');

    await applyUpdaterFileModes(posixPrivateFileMode, <String>[
      file.path,
    ], null);

    expect(file.statSync().mode & 0x1FF, posixPrivateFileMode);
    expect(runner.startCalls, 0);
  });

  test(
    'stops applying file modes when cancellation is already requested',
    () async {
      final token = updater.UpdateCancellationToken()..cancel();
      final directory = await Directory.systemTemp.createTemp(
        'alera-updater-mode',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/staged-file')
        ..writeAsStringSync('data');

      await expectLater(
        applyUpdaterFileModes(posixPrivateFileMode, <String>[file.path], token),
        throwsA(isA<updater.UpdateCancelledException>()),
      );
    },
  );
}

Future<_RunOutcome> _capture(Future<ProcessResult> future) async {
  try {
    return _RunOutcome(value: await future);
  } catch (error, stackTrace) {
    return _RunOutcome(error: error, stackTrace: stackTrace);
  }
}

class _RunOutcome {
  const _RunOutcome({this.value, this.error, this.stackTrace});

  final ProcessResult? value;
  final Object? error;
  final StackTrace? stackTrace;
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner(this.process);

  final _FakeStartedProcess process;
  final Completer<void> _started = Completer<void>();
  int startCalls = 0;
  String? executable;
  List<String>? arguments;

  Future<void> get started => _started.future;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    startCalls += 1;
    this.executable = executable;
    this.arguments = arguments.toList(growable: false);
    if (!_started.isCompleted) {
      _started.complete();
    }
    return process.startedProcess;
  }
}

class _FakeStartedProcess {
  _FakeStartedProcess();

  final int pid = 7123;
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final Completer<void> killedSignal = Completer<void>();
  final List<List<int>> stdinWrites = <List<int>>[];
  Object? stdinCloseError;
  Object? killError;
  int stdinCloseCalls = 0;
  int killCalls = 0;
  bool killed = false;
  bool stdinClosed = false;

  StartedProcess get startedProcess => StartedProcess(
    stdinWrite: (data) => stdinWrites.add(data.toList(growable: false)),
    stdinClose: () {
      stdinCloseCalls += 1;
      final error = stdinCloseError;
      if (error != null) {
        throw error;
      }
      stdinClosed = true;
    },
    stdout: stdoutController.stream,
    stderr: stderrController.stream,
    pid: pid,
    exitCode: _exitCode.future,
    kill: ([dynamic signal]) {
      killCalls += 1;
      killed = true;
      if (!killedSignal.isCompleted) {
        killedSignal.complete();
      }
      final error = killError;
      if (error != null) {
        throw error;
      }
      return true;
    },
  );

  void completeExit([int code = 0]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
  }

  Future<void> closeOutput() async {
    await stdoutController.close();
    await stderrController.close();
  }

  Future<void> dispose() async {
    completeExit(143);
    unawaited(stdoutController.close());
    unawaited(stderrController.close());
  }
}
