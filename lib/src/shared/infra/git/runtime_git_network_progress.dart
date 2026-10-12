part of 'runtime_git_backend.dart';

mixin _RuntimeGitNetworkProgress implements GitNetworkProgressBackend {
  RuntimeHostClient get _client;
  Future<void> Function()? get beforeAccess;
  Future<Object?> _request(
    String type,
    String? path, [
    Map<String, Object?> fields = const {},
    Duration timeout = _gitRequestTimeout,
  ]);
  @override
  Future<void> networkWithProgress(
    String path, {
    required bool push,
    required void Function(String line) onOutput,
  }) async {
    await beforeAccess?.call();
    final client = _client;
    final capable =
        client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          'gitOperationsProgressV1',
        );
    if (!capable) {
      await _request(
        push ? 'git.push' : 'git.pull',
        path,
        const {},
        _gitNetworkTimeout,
      );
      return;
    }
    final id = const Uuid().v4();
    var finished = false;
    String? previous;
    Future<void> poll() async {
      try {
        final value = await _request('git.networkProgress', path, {
          'operationId': id,
        });
        if (finished) return;
        final line = value is Map ? value['line'] : null;
        if (line is String && line != previous) {
          previous = line;
          onOutput(line);
        }
      } catch (_) {
        /* The operation response owns connection failures. */
      }
    }

    Future<void> watch() async {
      while (!finished) {
        await Future.pause(const Duration(milliseconds: 500));
        if (!finished) await poll();
      }
    }

    unawaited(watch());
    try {
      await _request(
        push ? 'git.pushWithProgress' : 'git.pullWithProgress',
        path,
        {'operationId': id},
        _gitNetworkTimeout,
      );
      await poll();
    } finally {
      finished = true;
    }
  }
}
