import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/agent_status/infra/agent_awake_assertions.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MacosSystemSleepAssertion', () {
    test('spawns caffeinate with system and idle sleep assertions', () async {
      final runner = _FakeProcessRunner()
        ..queuedStarts.add(_FakeStartedProcess());
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
      );

      await assertion.start('status-change');

      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.executable, '/usr/bin/caffeinate');
      expect(runner.calls.single.arguments, <String>['-i', '-s']);
    });

    test('is a no-op off macOS', () async {
      final runner = _FakeProcessRunner();
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'linux',
      );

      await assertion.start('status-change');

      expect(runner.calls, isEmpty);
    });

    test('does not start a second process while one is live', () async {
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[
          _FakeStartedProcess(),
          _FakeStartedProcess(),
        ]);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
      );

      await assertion.start('status-change');
      await assertion.start('status-change');

      expect(runner.calls, hasLength(1));
    });

    test('stops a process that finishes spawning after stop', () async {
      final child = _FakeStartedProcess();
      final pending = Completer<StartedProcess>();
      final runner = _FakeProcessRunner()..queuedStarts.add(pending.future);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
      );

      final start = assertion.start('status-change');
      await _waitForStartCalls(runner, 1);
      final stop = assertion.stop('status-change');
      pending.complete(child.startedProcess);
      await Future.wait<void>(<Future<void>>[start, stop]);

      expect(runner.calls, hasLength(1));
      expect(child.killCalls, 1);
    });

    test('retries after an unexpected process exit', () async {
      final first = _FakeStartedProcess();
      final second = _FakeStartedProcess();
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[first, second]);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      first.completeExit(1);
      await _waitForStartCalls(runner, 2);

      expect(runner.calls, hasLength(2));
    });

    test('coalesces starts while waiting for a retry window', () async {
      var now = DateTime.utc(2026, 5, 27, 12);
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[
          const ProcessException('/usr/bin/caffeinate', <String>[], 'boom'),
          _FakeStartedProcess(),
        ]);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
        now: () => now,
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      await assertion.start('status-change');
      now = now.add(const Duration(milliseconds: 6));
      await _waitForStartCalls(runner, 2);

      expect(runner.calls, hasLength(2));
    });

    test('handles exit-code future failures once', () async {
      final first = _FakeStartedProcess();
      final second = _FakeStartedProcess();
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[first, second]);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      first.completeExitError(StateError('exit failed'));
      first.completeExit(1);
      await _waitForStartCalls(runner, 2);

      expect(runner.calls, hasLength(2));
    });

    test('does not retry an intentional stop', () async {
      final first = _FakeStartedProcess();
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[first, _FakeStartedProcess()]);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      await assertion.stop('settings-change');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(first.killCalls, 1);
      expect(runner.calls, hasLength(1));
    });

    test('logs kill failures without retrying', () async {
      final first = _FakeStartedProcess()..throwOnKill = true;
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[first, _FakeStartedProcess()]);
      final assertion = MacosSystemSleepAssertion(
        processRunner: runner,
        platform: 'macos',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      await assertion.stop('settings-change');
      first.completeExit(143);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(first.killCalls, 1);
      expect(runner.calls, hasLength(1));
    });

    test(
      'suppresses repeated warning-level logs for the same failure',
      () async {
        final runner = _FakeProcessRunner()
          ..queuedStarts.addAll(<Object>[
            const ProcessException('/usr/bin/caffeinate', <String>[], 'boom'),
            const ProcessException('/usr/bin/caffeinate', <String>[], 'boom'),
            _FakeStartedProcess(),
          ]);
        final assertion = MacosSystemSleepAssertion(
          processRunner: runner,
          platform: 'macos',
          retryDelay: .zero,
        );

        await assertion.start('status-change');
        await _waitForStartCalls(runner, 3);

        expect(runner.calls, hasLength(3));
      },
    );
  });

  group('WindowsSystemSleepAssertion', () {
    test('sets system and display required execution state', () async {
      final calls = <int>[];
      final assertion = WindowsSystemSleepAssertion(
        platform: 'windows',
        setExecutionState: (flags) {
          calls.add(flags);
          return 1;
        },
      );

      await assertion.start('status-change');

      expect(calls, <int>[0x80000003]);
    });

    test('is a no-op off Windows', () async {
      final assertion = WindowsSystemSleepAssertion(
        platform: 'linux',
        setExecutionState: (_) => throw StateError('should not be called'),
      );

      await assertion.start('status-change');
      await assertion.stop('settings-change');
    });

    test('does not set execution state again while active', () async {
      final calls = <int>[];
      final assertion = WindowsSystemSleepAssertion(
        platform: 'windows',
        setExecutionState: (flags) {
          calls.add(flags);
          return 1;
        },
      );

      await assertion.start('status-change');
      await assertion.start('status-change');

      expect(calls, <int>[0x80000003]);
    });

    test('clears the execution state on stop', () async {
      final calls = <int>[];
      final assertion = WindowsSystemSleepAssertion(
        platform: 'windows',
        setExecutionState: (flags) {
          calls.add(flags);
          return 1;
        },
      );

      await assertion.start('status-change');
      await assertion.stop('settings-change');

      expect(calls, <int>[0x80000003, 0x80000000]);
    });

    test('clears the execution state on dispose', () async {
      final calls = <int>[];
      final assertion = WindowsSystemSleepAssertion(
        platform: 'windows',
        setExecutionState: (flags) {
          calls.add(flags);
          return 1;
        },
      );

      await assertion.start('status-change');
      await assertion.dispose();

      expect(calls, <int>[0x80000003, 0x80000000]);
    });

    test('can retry after a failed start', () async {
      final calls = <int>[];
      var attempts = 0;
      final assertion = WindowsSystemSleepAssertion(
        platform: 'windows',
        setExecutionState: (flags) {
          calls.add(flags);
          attempts++;
          return attempts == 1 ? 0 : 1;
        },
      );

      await assertion.start('status-change');
      await assertion.start('status-change');

      expect(calls, <int>[0x80000003, 0x80000003]);
    });

    test('logs execution-state exceptions and can retry', () async {
      final calls = <int>[];
      var attempts = 0;
      final assertion = WindowsSystemSleepAssertion(
        platform: 'windows',
        setExecutionState: (flags) {
          calls.add(flags);
          attempts++;
          if (attempts == 1) {
            throw StateError('kernel call failed');
          }
          return 1;
        },
      );

      await assertion.start('status-change');
      await assertion.start('status-change');

      expect(calls, <int>[0x80000003, 0x80000003]);
    });
  });
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
    bool includeParentEnvironment = true,
  }) async {
    calls.add(_StartCall(executable, List<String>.from(arguments)));
    final next = queuedStarts.isEmpty
        ? _FakeStartedProcess()
        : queuedStarts.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    if (next is Future<StartedProcess>) {
      return next;
    }
    return (next as _FakeStartedProcess).startedProcess;
  }
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

class _FakeStartedProcess() {
  this {
    startedProcess = StartedProcess(
      stdinWrite: (_) {},
      stdout: const Stream<List<int>>.empty(),
      stderr: const Stream<List<int>>.empty(),
      pid: 123,
      exitCode: _exitCode.future,
      kill: ([dynamic signal]) {
        killCalls++;
        if (throwOnKill) {
          throw StateError('kill failed');
        }
        completeExit(143);
        return true;
      },
    );
  }

  final Completer<int> _exitCode = Completer<int>();
  late final StartedProcess startedProcess;
  int killCalls = 0;
  var throwOnKill = false;

  void completeExit(int exitCode) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(exitCode);
    }
  }

  void completeExitError(Object error) {
    if (!_exitCode.isCompleted) {
      _exitCode.completeError(error, .current);
    }
  }
}

class const _StartCall(final String executable, final List<String> arguments);
