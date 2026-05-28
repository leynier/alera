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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
  });

  group('LinuxLidSleepAssertion', () {
    test(
      'spawns systemd-inhibit with sleep and lid-switch inhibitors',
      () async {
        final runner = _FakeProcessRunner()
          ..queuedStarts.add(_FakeStartedProcess());
        final assertion = LinuxLidSleepAssertion(
          processRunner: runner,
          platform: 'linux',
        );

        await assertion.start('status-change');

        expect(runner.calls, hasLength(1));
        expect(runner.calls.single.executable, 'systemd-inhibit');
        expect(runner.calls.single.arguments, <String>[
          '--what=sleep:handle-lid-switch',
          '--who=Alera',
          '--why=Agents are working',
          '--mode=block',
          'sleep',
          'infinity',
        ]);
      },
    );

    test('degrades to no-op when systemd-inhibit is missing', () async {
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

    test('treats shell command-not-found exits as unavailable', () async {
      final first = _FakeStartedProcess();
      final runner = _FakeProcessRunner()
        ..queuedStarts.addAll(<Object>[first, _FakeStartedProcess()]);
      final assertion = LinuxLidSleepAssertion(
        processRunner: runner,
        platform: 'linux',
        retryDelay: const Duration(milliseconds: 5),
      );

      await assertion.start('status-change');
      first.completeExit(127);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await assertion.start('power-resume');

      expect(runner.calls, hasLength(1));
    });
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
}
