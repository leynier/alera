part of 'rust_git_backend.dart';

mixin _RustGitNetworkProgress on _RustGitBackendHostedReview
    implements GitNetworkProgressBackend {
  @override
  Future<void> networkWithProgress(
    String path, {
    required bool push,
    required void Function(String line) onOutput,
  }) async {
    var done = false;
    await for (final raw in network_rust.gitNetworkProgress(
      path: path,
      push: push,
    )) {
      final record = jsonDecode(raw) as Map<String, dynamic>;
      if (record['line'] case final String line) onOutput(line);
      if (record['done'] == true) {
        done = true;
        if (record['error'] case final String message) {
          throw _toException(
            rust.GitError(
              kind:
                  rust.GitErrorKind.values
                      .where((kind) => kind.name == record['errorKind'])
                      .firstOrNull ??
                  rust.GitErrorKind.internal,
              context: message,
            ),
          );
        }
      }
    }
    if (!done) {
      throw const GitCliException(
        'The Git progress stream disconnected. Review the repository before retrying.',
      );
    }
  }
}
