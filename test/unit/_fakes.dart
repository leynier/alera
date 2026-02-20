import 'dart:async';

import 'package:alera/src/features/worktree/application/branch_name_generator.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';

class InMemoryStringStore implements StringStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}

class ProcessCall {
  const ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class FakeProcessRunner implements ProcessRunner {
  final List<ProcessCall> calls = <ProcessCall>[];
  final List<ProcessRunOutput> queuedResults = <ProcessRunOutput>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      ProcessCall(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
      ),
    );

    if (queuedResults.isEmpty) {
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    return queuedResults.removeAt(0);
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError('start not used in these tests');
  }
}

class FakeBranchNameGenerator implements BranchNameResolver {
  FakeBranchNameGenerator(this.value);

  final String value;

  @override
  Future<String> generate({
    required String firstPrompt,
    required DateTime now,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return value;
  }
}
