import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';

/// How long a cached title and state are trusted before a visible window
/// fetches them again.
const Duration linkedIssueStaleAfter = Duration(minutes: 30);

/// How often a visible window looks for stale linked issues.
const Duration linkedIssueRefreshInterval = Duration(minutes: 15);

/// Keeps cached issue titles and states from going stale while the window is
/// visible, one fetch at a time so a sidebar full of issues never fans out
/// into parallel forge CLI processes. Parks while the window is hidden, like
/// the update check, and runs a pass as soon as it becomes visible again.
class LinkedIssueMetadataRefresher({
  required this._list,
  required this._refresh,
  required AppForeground foreground,
  DateTime Function()? now,
  this.interval = linkedIssueRefreshInterval,
  this.staleAfter = linkedIssueStaleAfter,
}) {
  this : _now = now ?? DateTime.now {
    _foregroundChanges = foreground.changes.listen(_applyForeground);
    if (foreground.isForeground) {
      _start();
    }
  }

  final Future<Map<String, LinkedIssue>> Function() _list;
  final Future<void> Function(String workspaceId) _refresh;
  final DateTime Function() _now;
  final Duration interval;
  final Duration staleAfter;

  Timer? _timer;
  StreamSubscription<bool>? _foregroundChanges;
  Future<void>? _pass;
  var _disposed = false;

  bool get isRunning => _timer != null;

  /// Refreshes every stale link once. Concurrent calls share one pass.
  Future<void> runPass() =>
      _pass ??= _runPass().whenComplete(() => _pass = null);

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_foregroundChanges?.cancel());
    _foregroundChanges = null;
  }

  void _applyForeground(bool isForeground) {
    if (_disposed) {
      return;
    }
    if (isForeground) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    if (_disposed || _timer != null) {
      return;
    }
    _timer = Timer.periodic(interval, (_) => unawaited(runPass()));
    // Deferred: the refresher is created while its provider builds.
    scheduleMicrotask(() => unawaited(runPass()));
  }

  Future<void> _runPass() async {
    if (_disposed) {
      return;
    }
    final Map<String, LinkedIssue> issues;
    try {
      issues = await _list();
    } on Object {
      return;
    }
    for (final issue in issues.values) {
      if (_disposed || _timer == null) {
        return;
      }
      if (!_isStale(issue)) {
        continue;
      }
      try {
        await _refresh(issue.workspaceId);
      } on Object {
        // A missing CLI or a signed-out forge is recorded on the link by the
        // host; the next pass tries again.
      }
    }
  }

  bool _isStale(LinkedIssue issue) {
    if (!issue.isFetchable) {
      return false;
    }
    final fetchedAt = issue.fetchedAt ?? issue.linkedAt;
    return _now().difference(fetchedAt) >= staleAfter;
  }
}
