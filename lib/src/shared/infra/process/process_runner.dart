import 'dart:async';

class ProcessRunOutput {
  const ProcessRunOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class StartedProcess {
  StartedProcess({
    required this.stdinWrite,
    this.stdinClose = _noopStdinClose,
    required this.stdout,
    required this.stderr,
    required this.pid,
    required this.exitCode,
    required this.kill,
  });

  final void Function(List<int> data) stdinWrite;
  final void Function() stdinClose;
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final int pid;
  final Future<int> exitCode;
  final bool Function([dynamic signal]) kill;
}

void _noopStdinClose() {}

abstract interface class ProcessRunner {
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  });
}
