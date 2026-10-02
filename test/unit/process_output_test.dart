import 'dart:io';

import 'package:alera/src/shared/infra/process/process_output.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards an explicit budget and timeout to a capable runner', () async {
    final runner = _BoundedFakeRunner();

    final result = await runProcessWithOutputBudget(
      runner,
      'probe',
      const <String>['--json'],
      workingDirectory: '/tmp/workspace',
      environment: const <String, String>{'MODE': 'test'},
      maxOutputBytes: 2 * 1024 * 1024,
      timeout: const Duration(seconds: 4),
    );

    expect(result.stdout, 'bounded');
    expect(runner.maxOutputBytes, 2 * 1024 * 1024);
    expect(runner.timeout, const Duration(seconds: 4));
    expect(runner.workingDirectory, '/tmp/workspace');
    expect(runner.environment, const <String, String>{'MODE': 'test'});
  });

  test('keeps a non-capable runner on its default run contract', () async {
    final runner = _BaseFakeRunner();

    final result = await runProcessWithOutputBudget(
      runner,
      'probe',
      const <String>[],
      maxOutputBytes: processRunDefaultMaxOutputBytes,
    );

    expect(result.stderr, 'fallback');
    expect(runner.runCalls, 1);
  });

  test('rejects a custom contract when the runner cannot honor it', () {
    final runner = _BaseFakeRunner();

    expect(
      () => runProcessWithOutputBudget(
        runner,
        'probe',
        const <String>[],
        maxOutputBytes: 1024,
      ),
      throwsA(isA<ProcessException>()),
    );
    expect(runner.runCalls, 0);
  });

  test('rejects an unbounded or empty budget before dispatch', () {
    final runner = _BoundedFakeRunner();

    expect(
      () => runProcessWithOutputBudget(
        runner,
        'probe',
        const <String>[],
        maxOutputBytes: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => runProcessWithOutputBudget(
        runner,
        'probe',
        const <String>[],
        maxOutputBytes: processRunMaximumOutputBytes + 1,
      ),
      throwsArgumentError,
    );
    expect(runner.calls, 0);
  });
}

class _BaseFakeRunner implements ProcessRunner {
  int runCalls = 0;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    runCalls += 1;
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: 'fallback');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    return Future<StartedProcess>.error(StateError('not used'));
  }
}

class _BoundedFakeRunner extends _BaseFakeRunner
    implements ProcessRunnerWithOutputBudget {
  int? maxOutputBytes;
  Duration? timeout;
  String? workingDirectory;
  Map<String, String>? environment;

  int get calls => runWithOutputBudgetCalls;

  int runWithOutputBudgetCalls = 0;

  @override
  Future<ProcessRunOutput> runWithOutputBudget(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required int maxOutputBytes,
    Duration? timeout,
  }) async {
    runWithOutputBudgetCalls += 1;
    this.maxOutputBytes = maxOutputBytes;
    this.timeout = timeout;
    this.workingDirectory = workingDirectory;
    this.environment = environment;
    return const ProcessRunOutput(exitCode: 0, stdout: 'bounded', stderr: '');
  }
}
