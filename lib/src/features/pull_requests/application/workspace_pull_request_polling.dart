part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestPolling on _$WorkspacePullRequestController {
  WorkspacePullRequestController get _polling =>
      this as WorkspacePullRequestController;

  Future<void> _refresh({required _RefreshOrigin origin}) {
    if (!_polling._shouldPoll) {
      return Future<void>.value();
    }
    final current = state.value;
    if (current == null ||
        (current.isBusy && current.action != PullRequestAction.refresh)) {
      return Future<void>.value();
    }
    final inFlight = _polling._refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final operation = _performRefresh(current: current, origin: origin);
    _polling._refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_polling._refreshInFlight, operation)) {
        _polling._refreshInFlight = null;
      }
    });
  }

  Future<void> _performRefresh({
    required WorkspacePullRequestState current,
    required _RefreshOrigin origin,
  }) async {
    _polling._pollTimer?.cancel();
    if (origin != _RefreshOrigin.poll) {
      _resetPollInterval();
    }
    state = AsyncData(current.copyWith(action: .refresh, clearError: true));

    try {
      final reloaded = await _polling._loader.load(_polling.scope);
      if (_polling._disposed) {
        return;
      }
      final failed = reloaded.errorMessage != null;
      final visibleReload = _polling._applyPendingCommentBodies(reloaded);
      state = AsyncData(
        failed
            ? current.copyWith(
                clearAction: true,
                errorMessage: reloaded.errorMessage,
              )
            : visibleReload,
      );
      if (origin == _RefreshOrigin.poll) {
        _advancePollInterval(
          changed:
              !failed && visibleReload.pollSignature != current.pollSignature,
        );
      }
    } catch (error) {
      if (!_polling._disposed) {
        state = AsyncData(
          current.copyWith(clearAction: true, errorMessage: error.toString()),
        );
        if (origin == _RefreshOrigin.poll) {
          _advancePollInterval(changed: false);
        }
      }
    } finally {
      _schedulePoll(_polling.scope);
    }
  }

  void _resetPollInterval() =>
      _polling._pollInterval = WorkspacePullRequestController._minPollInterval;

  void _advancePollInterval({required bool changed}) {
    if (changed) {
      _resetPollInterval();
      return;
    }
    final doubled = _polling._pollInterval * 2;
    _polling._pollInterval =
        doubled > WorkspacePullRequestController._maxPollInterval
        ? WorkspacePullRequestController._maxPollInterval
        : doubled;
  }

  void _schedulePoll(
    WorkspacePullRequestScope scope, {
    WorkspacePullRequestState? snapshot,
  }) {
    _polling._pollTimer?.cancel();
    final current = snapshot ?? state.value;
    if (!_polling._shouldPoll || current == null || current.isBusy) {
      return;
    }
    // Missing identity or auth can heal outside the app (the user signs in,
    // adds a remote); keep polling slowly instead of never retrying.
    final degraded =
        current.identity == null ||
        current.authStatus != ForgeAuthStatus.authenticated;
    _polling._pollTimer = Timer(
      degraded
          ? WorkspacePullRequestController._maxPollInterval
          : _polling._pollInterval,
      () {
        unawaited(_pollTick(scope));
      },
    );
  }

  Future<void> _pollTick(WorkspacePullRequestScope scope) async {
    _polling._pollTimer = null;
    await _refresh(origin: .poll);
  }
}

enum _RefreshOrigin { manual, poll, resume }
