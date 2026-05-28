part of 'workbench_controller_test.dart';

class _FakeProcessRunner implements ProcessRunner {
  String currentBranch = 'main';
  bool createGitClone = false;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (arguments.length >= 2 &&
        arguments[0] == 'branch' &&
        arguments[1] == '--show-current') {
      return ProcessRunOutput(
        exitCode: 0,
        stdout: '$currentBranch\n',
        stderr: '',
      );
    }
    if (arguments.contains('for-each-ref')) {
      return const ProcessRunOutput(
        exitCode: 0,
        stdout: 'main\norigin/main\n',
        stderr: '',
      );
    }
    if (arguments.length >= 2 &&
        arguments[0] == 'rev-parse' &&
        arguments.contains('--verify')) {
      // No branch with the requested name exists yet.
      return const ProcessRunOutput(exitCode: 1, stdout: '', stderr: '');
    }
    if (arguments.length >= 3 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'list') {
      return ProcessRunOutput(
        exitCode: 0,
        stdout:
            'worktree ${workingDirectory ?? ''}\nbranch refs/heads/main\n\n',
        stderr: '',
      );
    }
    if (arguments.isNotEmpty && arguments[0] == 'clone') {
      if (createGitClone && arguments.length >= 4) {
        final destination = arguments.last;
        Directory(p.join(destination, '.git')).createSync(recursive: true);
      }
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
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
