import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );

    return ProcessRunOutput(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );

    return StartedProcess(
      stdinWrite: (data) => process.stdin.add(data),
      stdinClose: process.stdin.close,
      stdout: process.stdout,
      stderr: process.stderr,
      pid: process.pid,
      exitCode: process.exitCode,
      kill: ([signal]) => process.kill(
        signal is ProcessSignal ? signal : ProcessSignal.sigterm,
      ),
    );
  }
}
