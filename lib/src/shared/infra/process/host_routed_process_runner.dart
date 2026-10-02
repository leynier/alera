import 'dart:io';

import 'package:alera/src/shared/infra/process/process_output.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// Resolves the runner for a working directory: the remote runner when the
/// directory belongs to a workspace on another host, null otherwise.
typedef RemoteProcessRunnerResolver = ProcessRunner? Function(
  String workingDirectory,
);

/// [ProcessRunner] for tools that act on a checkout. A working directory
/// inside a remote workspace sends the command to that workspace's host;
/// anything else, including a command with no working directory, runs here.
///
/// Only workspace-scoped consumers take this runner (the forge providers).
/// The updater, font and CLI installers, quota polls and everything else that
/// is about this machine keep the local runner.
class const HostRoutedProcessRunner({
  required final ProcessRunner local,
  required final RemoteProcessRunnerResolver remoteFor,
}) implements ProcessRunner, ProcessRunnerWithOutputBudget {
  ProcessRunner _for(String? workingDirectory) {
    if (workingDirectory == null || workingDirectory.trim().isEmpty) {
      return local;
    }
    return remoteFor(workingDirectory) ?? local;
  }

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => _for(workingDirectory).run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  @override
  Future<ProcessRunOutput> runWithOutputBudget(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required int maxOutputBytes,
    Duration? timeout,
  }) {
    final runner = _for(workingDirectory);
    if (runner case final ProcessRunnerWithOutputBudget bounded) {
      return bounded.runWithOutputBudget(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        maxOutputBytes: maxOutputBytes,
        timeout: timeout,
      );
    }
    if (maxOutputBytes != processRunDefaultMaxOutputBytes || timeout != null) {
      return Future<ProcessRunOutput>.error(
        ProcessException(
          executable,
          arguments,
          'The selected process host cannot honor the requested output '
          'budget or timeout.',
        ),
      );
    }
    return runner.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) => _for(workingDirectory).start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
  );
}
