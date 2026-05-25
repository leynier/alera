import 'dart:async';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'github_star_controller.g.dart';

enum GitHubStarState { loading, notStarred, starring, starred, error, hidden }

@Riverpod(keepAlive: true)
class GitHubStarController extends _$GitHubStarController {
  bool _disposed = false;
  bool _refreshStarted = false;

  GitHubStarService get _service => ref.read(gitHubStarServiceProvider);

  @override
  GitHubStarState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
    });
    if (!_refreshStarted) {
      _refreshStarted = true;
      unawaited(refresh());
    }
    return GitHubStarState.loading;
  }

  Future<void> refresh() async {
    state = GitHubStarState.loading;
    final result = await _service.checkStarred();
    if (_disposed) return;
    if (result == null) {
      state = GitHubStarState.hidden;
    } else {
      state = result ? GitHubStarState.starred : GitHubStarState.notStarred;
    }
  }

  Future<void> star() async {
    if (state != GitHubStarState.notStarred && state != GitHubStarState.error) {
      return;
    }
    state = GitHubStarState.starring;
    final ok = await _service.star();
    if (_disposed) return;
    state = ok ? GitHubStarState.starred : GitHubStarState.error;
  }
}
