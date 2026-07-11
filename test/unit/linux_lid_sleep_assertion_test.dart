import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/agent_awake_assertions.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinuxLidSleepAssertion', () {
    test('runs a parent-bound inhibitor without sleep infinity', () async {
      final runner = _FakeProcessRunner();
      final assertion = LinuxLidSleepAssertion(
        processRunner: runner,
        processId: 4242,
        platform: 'linux',
      );

      await assertion.start('status-change');

      expect(runner.calls, <_StartCall>[
        const _StartCall('systemd-inhibit', <String>[
          '--what=sleep:handle-lid-switch',
          '--who=Alera',
          '--why=Agents are working',
          '--mode=block',
          'tail',
          '--pid=4242',
          '-f',
          '/dev/null',
        ]),
      ]);
    });

    test('is a no-op off Linux', () async {
      final runner = _FakeProcessRunner();
      final assertion = LinuxLidSleepAssertion(
        processRunner: runner,
        platform: 'macos',
      );

      await assertion.start('status-change');

      expect(runner.calls, isEmpty);
    });

    test('coalesces concurrent starts into one helper', () async {
      final runner = _FakeProcessRunner();
      final assertion = LinuxLidSleepAssertion(
        processRunner: runner,
        platform: 'linux',
      );

      await Future.wait<void>(<Future<void>>[
        assertion.start('status-change'),
        assertion.start('status-change'),
        assertion.start('status-change'),
      ]);

      expect(runner.calls, hasLength(1));
    });

    test('retries with a fresh helper after an unexpected exit', () async {
      final first = _FakeStartedProcess();
      final second = _FakeStartedProcess();
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[first, second]);
      final assertion = LinuxLidSleepAssertion(
        processRunner: runner,
        platform: 'linux',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      first.completeExit(1);
      await _waitForStartCalls(runner, 2);

      expect(runner.calls, hasLength(2));
      await assertion.dispose();
    });

    test('does not retry when systemd-inhibit is unavailable', () async {
      final runner = _FakeProcessRunner()
        ..queuedStarts.add(
          const ProcessException('systemd-inhibit', <String>[], 'not found', 2),
        );
      final assertion = LinuxLidSleepAssertion(
        processRunner: runner,
        platform: 'linux',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await assertion.start('power-resume');

      expect(runner.calls, hasLength(1));
    });
  });
}

Future<void> _waitForStartCalls(
  _FakeProcessRunner runner,
  int count, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (runner.calls.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_StartCall> calls = <_StartCall>[];
  final List<Object> queuedStarts = <Object>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(_StartCall(executable, List<String>.from(arguments)));
    final next = queuedStarts.isEmpty
        ? _FakeStartedProcess()
        : queuedStarts.removeAt(0);
    if (next is ProcessException) {
      throw next;
    }
    return (next as _FakeStartedProcess).startedProcess;
  }
}

class _FakeStartedProcess {
  _FakeStartedProcess() {
    startedProcess = StartedProcess(
      stdinWrite: (_) {},
      stdout: const Stream<List<int>>.empty(),
      stderr: const Stream<List<int>>.empty(),
      pid: 123,
      exitCode: _exitCode.future,
      kill: ([dynamic signal]) {
        killCalls++;
        completeExit(143);
        return true;
      },
    );
  }

  final Completer<int> _exitCode = Completer<int>();
  late final StartedProcess startedProcess;
  int killCalls = 0;

  void completeExit(int exitCode) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(exitCode);
    }
  }
}

class _StartCall {
  const _StartCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  @override
  bool operator ==(Object other) {
    return other is _StartCall &&
        other.executable == executable &&
        _listEquals(other.arguments, arguments);
  }

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
