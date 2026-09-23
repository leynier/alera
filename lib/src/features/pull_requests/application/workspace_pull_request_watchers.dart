part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestWatchers on _WorkspacePullRequestPolling {
  WorkspacePullRequestController get _watchers =>
      this as WorkspacePullRequestController;

  var _watcherCount = 0;

  bool get _shouldPoll =>
      !_watchers._disposed && (_watchers._visible || _watcherCount > 0);

  /// Keeps check polling alive for Watch and Fix after the panel closes.
  void attachWatcher() {
    if (_watchers._disposed) {
      return;
    }
    _watcherCount++;
    if (_watcherCount == 1 && !_watchers._visible) {
      _resetPollInterval();
      _schedulePoll(_watchers.scope);
    }
  }

  void detachWatcher() {
    if (_watcherCount > 0) {
      _watcherCount--;
    }
    if (!_shouldPoll) {
      _watchers._pollTimer?.cancel();
    }
  }
}
