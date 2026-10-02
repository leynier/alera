import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kills a proxy that exceeds the response budget', () async {
    final chunk = List<int>.filled(64 * 1024, 120);
    final stderr = StreamController<List<int>>();
    final exit = Completer<int>();
    addTearDown(() async {
      await stderr.close();
      if (!exit.isCompleted) {
        exit.complete(143);
      }
    });
    final runner = _RecordingRunner(
      stdoutStream: Stream<List<int>>.fromIterable(
        Iterable<List<int>>.generate(
          (runtimeProxyMaxResponseBytes ~/ chunk.length) + 1,
          (_) => chunk,
        ),
      ),
      stderrStream: stderr.stream,
      exitCodeFuture: exit.future,
    );

    await expectLater(
      _client(runner).request(
        hostId: 'local',
        target: null,
        type: 'agentQuota.fetch',
        payload: const <String, Object?>{},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('returned too much data'),
        ),
      ),
    );
    expect(runner.killed, isTrue);
  });

  test('preserves UTF-8 when a response splits a code point', () async {
    final bytes = utf8.encode('{"id":1,"ok":true,"payload":{"note":"café"}}\n');
    final split = bytes.indexOf(0xC3) + 1;
    final runner = _RecordingRunner(
      stdoutStream: Stream<List<int>>.fromIterable(<List<int>>[
        bytes.sublist(0, split),
        bytes.sublist(split),
      ]),
    );

    final payload = await _client(runner).request(
      hostId: 'local',
      target: null,
      type: 'agentQuota.fetch',
      payload: const <String, Object?>{},
    );

    expect(payload['note'], 'café');
  });

  test('kills a timed-out proxy when stderr never closes', () async {
    final stderr = StreamController<List<int>>();
    final exit = Completer<int>();
    addTearDown(() async {
      await stderr.close();
      if (!exit.isCompleted) {
        exit.complete(143);
      }
    });
    final runner = _RecordingRunner(
      stderrStream: stderr.stream,
      exitCodeFuture: exit.future,
    );

    await expectLater(
      _client(runner).request(
        hostId: 'local',
        target: null,
        type: 'agentQuota.fetch',
        payload: const <String, Object?>{},
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(runner.killed, isTrue);
  });

  test('kills the proxy when stdout is malformed UTF-8', () async {
    final stderr = StreamController<List<int>>();
    final exit = Completer<int>();
    addTearDown(() async {
      await stderr.close();
      if (!exit.isCompleted) {
        exit.complete(143);
      }
    });
    final runner = _RecordingRunner(
      stdoutStream: Stream<List<int>>.value(<int>[0xFF]),
      stderrStream: stderr.stream,
      exitCodeFuture: exit.future,
    );

    await expectLater(
      _client(runner).request(
        hostId: 'local',
        target: null,
        type: 'agentQuota.fetch',
        payload: const <String, Object?>{},
      ),
      throwsA(isA<FormatException>()),
    );
    expect(runner.killed, isTrue);
  });

  test('kills the proxy when stderr is malformed UTF-8', () async {
    final exit = Completer<int>();
    final runner = _RecordingRunner(
      stdoutStream: Stream<List<int>>.value(
        utf8.encode('{"id":1,"ok":true,"payload":{}}\n'),
      ),
      stderrStream: Stream<List<int>>.value(<int>[0xFF]),
      exitCodeFuture: exit.future,
    );
    addTearDown(() {
      if (!exit.isCompleted) {
        exit.complete(143);
      }
    });

    await expectLater(
      _client(runner).request(
        hostId: 'local',
        target: null,
        type: 'agentQuota.fetch',
        payload: const <String, Object?>{},
      ),
      throwsA(isA<FormatException>()),
    );
    expect(runner.killed, isTrue);
  });

  test('cancels streams when a child reports a stream error', () async {
    final stdout = StreamController<List<int>>();
    final stderr = StreamController<List<int>>();
    final exit = Completer<int>();
    var stderrCanceled = false;
    stderr.onCancel = () {
      stderrCanceled = true;
    };
    addTearDown(() async {
      await stdout.close();
      await stderr.close();
      if (!exit.isCompleted) {
        exit.complete(143);
      }
    });
    final runner = _RecordingRunner(
      stdoutStream: stdout.stream,
      stderrStream: stderr.stream,
      exitCodeFuture: exit.future,
    );

    final request = _client(runner).request(
      hostId: 'local',
      target: null,
      type: 'agentQuota.fetch',
      payload: const <String, Object?>{},
    );
    stdout.addError(StateError('stdout pipe failed'));

    await expectLater(request, throwsA(isA<StateError>()));
    expect(runner.killed, isTrue);
    expect(stderrCanceled, isTrue);
  });
}

RuntimeProxyClient _client(ProcessRunner runner) => RuntimeProxyClient(
  processRunner: runner,
  cliResolver: const _Resolver(),
  applicationSupportDirectory: () async => Directory('/tmp/alera'),
);

class const _Resolver() implements AleraCliResolver {
  @override
  Future<AleraCliCommand> resolve({required String runtimeDir}) async {
    return const AleraCliCommand(
      executable: '/opt/alera',
      prefixArguments: <String>['--dev'],
    );
  }
}

class _RecordingRunner({
  this.stdoutStream,
  this.stderrStream,
  this.exitCodeFuture,
}) implements ProcessRunner {
  final Stream<List<int>>? stdoutStream;
  final Stream<List<int>>? stderrStream;
  final Future<int>? exitCodeFuture;
  bool killed = false;

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    return StartedProcess(
      stdinWrite: (_) {},
      stdout: stdoutStream ?? const Stream<List<int>>.empty(),
      stderr: stderrStream ?? const Stream<List<int>>.empty(),
      pid: 1,
      exitCode: exitCodeFuture ?? Future<int>.value(0),
      kill: ([signal]) {
        killed = true;
        return true;
      },
    );
  }

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}
