import 'dart:async';

import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:flutter_riverpod/legacy.dart';

enum GitHubStarState { loading, notStarred, starring, starred, error, hidden }

class GitHubStarController extends StateNotifier<GitHubStarState> {
  GitHubStarController(this._service, {bool refreshOnCreate = true})
    : super(GitHubStarState.loading) {
    if (refreshOnCreate) {
      unawaited(refresh());
    }
  }

  final GitHubStarService _service;

  Future<void> refresh() async {
    state = GitHubStarState.loading;
    final result = await _service.checkStarred();
    if (!mounted) return;
    if (result == null) {
      state = GitHubStarState.hidden;
    } else {
      state = result ? GitHubStarState.starred : GitHubStarState.notStarred;
    }
  }

  Future<void> star() async {
    if (state != GitHubStarState.notStarred &&
        state != GitHubStarState.error) {
      return;
    }
    state = GitHubStarState.starring;
    final ok = await _service.star();
    if (!mounted) return;
    state = ok ? GitHubStarState.starred : GitHubStarState.error;
  }
}
