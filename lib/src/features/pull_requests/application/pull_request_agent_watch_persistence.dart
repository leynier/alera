part of 'pull_request_agent_watch_providers.dart';

mixin _PullRequestAgentWatchPersistence on _$PullRequestAgentWatchController {
  final Set<String> _dirty = <String>{};

  void _persist(PullRequestAgentWatchSession session) {
    _dirty.add(session.workspaceId);
    unawaited(_push(session));
  }

  void _persistStop(String workspaceId) {
    _dirty.add(workspaceId);
    unawaited(_pushStop(workspaceId));
  }

  Future<void> _push(PullRequestAgentWatchSession session) async {
    try {
      final repository = ref.read(pullRequestAgentWatchRepositoryProvider);
      if (!await repository.isSupported()) {
        return;
      }
      await repository.upsert(PullRequestAgentWatchRecord.fromSession(session));
    } on Object {
      // Keep the in-memory watch if the host is gone or older.
    } finally {
      _dirty.remove(session.workspaceId);
    }
  }

  Future<void> _pushStop(String workspaceId) async {
    try {
      final repository = ref.read(pullRequestAgentWatchRepositoryProvider);
      if (!await repository.isSupported()) {
        return;
      }
      await repository.remove(workspaceId);
    } on Object {
      // Local stop already happened.
    } finally {
      _dirty.remove(workspaceId);
    }
  }
}
