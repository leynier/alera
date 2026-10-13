import 'dart:async';

import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'workspace_git_progress.g.dart';

class const WorkspaceGitProgressState({
  required this.id,
  required this.phase,
  required this.started,
  this.elapsed = Duration.zero,
  this.output,
  this.error,
  this.completed = false,
  this.retry,
}) {
  final int id;
  final String phase;
  final DateTime started;
  final Duration elapsed;
  final String? output;
  final String? error;
  final bool completed;
  final void Function()? retry;
  bool get running => !completed && error == null;
}

@Riverpod(keepAlive: true)
class WorkspaceGitProgress extends _$WorkspaceGitProgress {
  Timer? _timer;
  var _sequence = 0;
  @override
  WorkspaceGitProgressState? build(WorkspacePullRequestScope scope) {
    invalidateWhenWorkspaceRetired(ref, scope.workspaceId);
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  int start({void Function()? retry}) {
    _timer?.cancel();
    final id = ++_sequence;
    state = WorkspaceGitProgressState(
      id: id,
      phase: 'Preparing',
      started: DateTime.now(),
      retry: retry,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => update(id));
    return id;
  }

  void update(int id, {String? phase, String? output}) {
    if (!ref.mounted) return;
    final current = state;
    if (current == null || current.id != id || !current.running) return;
    state = WorkspaceGitProgressState(
      id: id,
      phase: phase ?? current.phase,
      started: current.started,
      elapsed: DateTime.now().difference(current.started),
      output: phase != null ? output : output ?? current.output,
      retry: current.retry,
    );
  }

  void finish(int id, {String? error}) {
    if (!ref.mounted || state?.id != id || state?.running != true) return;
    _timer?.cancel();
    final current = state!;
    state = WorkspaceGitProgressState(
      id: id,
      phase: error == null ? 'Completed' : current.phase,
      started: current.started,
      elapsed: DateTime.now().difference(current.started),
      output: current.output,
      error: error,
      completed: error == null,
      retry: current.retry,
    );
    if (error == null) {
      _timer = Timer(const Duration(seconds: 10), () {
        if (ref.mounted && state?.id == id) state = null;
      });
    }
  }

  void dismiss() {
    if (state?.running == true) return;
    _timer?.cancel();
    state = null;
  }
}
