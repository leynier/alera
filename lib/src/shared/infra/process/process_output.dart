import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

/// The combined stdout/stderr budget for ordinary commands.
const int processRunDefaultMaxOutputBytes = 16 * 1024 * 1024;

/// Prevents a per-call exception from turning the output collector back into
/// an unbounded capture.
const int processRunMaximumOutputBytes = 64 * 1024 * 1024;

/// Runs a command with the optional larger local output contract. A runner
/// without the capability may keep only its default bounded behavior; reject
/// requests that would otherwise be silently ignored.
Future<ProcessRunOutput> runProcessWithOutputBudget(
  ProcessRunner runner,
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  required int maxOutputBytes,
  Duration? timeout,
}) {
  if (maxOutputBytes <= 0 || maxOutputBytes > processRunMaximumOutputBytes) {
    throw ArgumentError.value(
      maxOutputBytes,
      'maxOutputBytes',
      'must be between 1 and $processRunMaximumOutputBytes bytes',
    );
  }
  final bounded = runner is ProcessRunnerWithOutputBudget
      ? runner as ProcessRunnerWithOutputBudget
      : null;
  if (bounded != null) {
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
    throw ProcessException(
      executable,
      arguments,
      'The selected process runner cannot honor the requested output budget '
      'or timeout.',
    );
  }
  return runner.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}
