import 'package:alera/src/shared/infra/git/git_backend.dart';

abstract interface class GitNetworkProgressBackend {
  Future<void> networkWithProgress(
    String path, {
    required bool push,
    required void Function(String line) onOutput,
  });
}

Future<void> runGitNetworkWithProgress(
  GitBackend git,
  String path, {
  required bool push,
  required void Function(String line) onOutput,
}) {
  if (git is GitNetworkProgressBackend) {
    return (git as GitNetworkProgressBackend).networkWithProgress(
      path,
      push: push,
      onOutput: onOutput,
    );
  }
  return push ? git.push(path) : git.pull(path);
}
