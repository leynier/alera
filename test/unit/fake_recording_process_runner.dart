import 'package:alera/src/shared/infra/process/process_runner.dart';

/// A [ProcessRunner] that records each `run` invocation and replays queued
/// results (a [ProcessRunOutput] to return, or an [Object] to throw). Shared by
/// the forge-provider command-construction suites.
class FakeRecordingProcessRunner implements ProcessRunner {
  FakeRecordingProcessRunner(this._results);

  final List<Object> _results;
  final List<RecordedProcessCall> calls = <RecordedProcessCall>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      RecordedProcessCall(
        executable: executable,
        arguments: List<String>.from(arguments),
        workingDirectory: workingDirectory,
        environment: environment == null
            ? null
            : Map<String, String>.from(environment),
      ),
    );
    final next = _results.removeAt(0);
    if (next is ProcessRunOutput) {
      return next;
    }
    throw next;
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

class RecordedProcessCall {
  const RecordedProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;

  /// The value passed to `--$flag`, or null when the flag is absent.
  String? optionValue(String flag) {
    final index = arguments.indexOf('--$flag');
    if (index < 0 || index + 1 >= arguments.length) {
      return null;
    }
    return arguments[index + 1];
  }
}
