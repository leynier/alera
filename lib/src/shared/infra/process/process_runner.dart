import 'dart:async';

class const ProcessRunOutput({
  required final int exitCode,
  required final String stdout,
  required final String stderr,
});

class StartedProcess({
  required final void Function(List<int> data) stdinWrite,
  final void Function() stdinClose = _noopStdinClose,
  required final Stream<List<int>> stdout,
  required final Stream<List<int>> stderr,
  required final int pid,
  required final Future<int> exitCode,
  required final bool Function([dynamic signal]) kill,
});

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
