import 'dart:async';

import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/forge_stack_provider.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/review_reference_parser.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_loader.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_refresh_signal.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/application/hosting_provider_resolver.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment_task_list.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_controller.g.dart';
part 'workspace_pull_request_review_actions.dart';
part 'workspace_pull_request_review_editing.dart';
part 'workspace_pull_request_ship_actions.dart';
part 'workspace_pull_request_stack_actions.dart';
part 'workspace_pull_request_stack_validation.dart';

@Riverpod(keepAlive: true)
class WorkspacePullRequestController extends _$WorkspacePullRequestController
    with
        _WorkspacePullRequestReviewActions,
        _WorkspacePullRequestReviewEditing,
        _WorkspacePullRequestShipActions,
        _WorkspacePullRequestStackActions {
  static const Duration _minPollInterval = Duration(seconds: 30);
  static const Duration _maxPollInterval = Duration(seconds: 120);

  late final GitBackend _gitBackend;
  late final ForgeProviderRegistry _registry;
  late final LinkedReviewRepository _linkedReviews;
  late final WorkspacePullRequestLoader _loader;

  Timer? _pollTimer;
  Duration _pollInterval = _minPollInterval;
  Future<void>? _refreshInFlight;
  final Map<String, _PendingReviewCommentSave> _pendingCommentSaves =
      <String, _PendingReviewCommentSave>{};
  final Set<String> _savingCommentIds = <String>{};
  var _panelViewCount = 0;
  bool _visible = false;
  bool _disposed = false;

  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async {
    invalidateWhenWorkspaceRetired(ref, scope.workspaceId);
    _gitBackend = ref.read(gitBackendProvider);
    _registry = ref.read(forgeProviderRegistryProvider);
    _linkedReviews = ref.read(linkedReviewRepositoryProvider);
    _loader = WorkspacePullRequestLoader(
      _gitBackend,
      _registry,
      _linkedReviews,
    );
    _visible = false;
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
      _pendingCommentSaves.clear();
      _savingCommentIds.clear();
    });
    final initial = _applyPendingCommentBodies(await _loader.load(scope));
    _schedulePoll(scope, snapshot: initial);
    return initial;
  }

  /// Reloads review + checks now.
  Future<void> refresh() => _refresh(origin: .manual);

  /// Marks one visible panel as attached and revalidates any cached snapshot.
  void attachPanel() {
    if (_disposed) {
      return;
    }
    _panelViewCount++;
    if (_panelViewCount > 1) {
      return;
    }
    _visible = true;
    _resetPollInterval();
    if (state.value != null) {
      Timer.run(() {
        if (!_disposed && _visible) {
          unawaited(_refresh(origin: .resume));
        }
      });
      return;
    }
    // A failed initial load leaves the provider in AsyncError with no timer;
    // without this recovery an opened panel would stay dead forever.
    if (state.hasError) {
      Timer.run(() {
        unawaited(_recoverFromError());
      });
    }
  }

  Future<void> _recoverFromError() async {
    if (_disposed || !_visible) {
      return;
    }
    try {
      final loaded = await _loader.load(scope);
      if (!_disposed) {
        state = AsyncData(_applyPendingCommentBodies(loaded));
      }
    } catch (error, stackTrace) {
      if (!_disposed) {
        state = AsyncError<WorkspacePullRequestState>(error, stackTrace);
      }
    } finally {
      if (!_disposed && _visible) {
        if (state.value != null) {
          _schedulePoll(scope);
        } else {
          // Still failing: keep retrying slowly while the panel stays open.
          _pollTimer?.cancel();
          _pollTimer = Timer(_maxPollInterval, () {
            unawaited(_recoverFromError());
          });
        }
      }
    }
  }

  /// Stops polling after the last visible panel for this scope is detached.
  void detachPanel() {
    if (_panelViewCount > 0) {
      _panelViewCount--;
    }
    if (_panelViewCount != 0) {
      return;
    }
    _visible = false;
    _pollTimer?.cancel();
  }

  /// Links the workspace to the review named by [reference] (`#123` or a URL).
  Future<void> link(String reference) {
    return _run(
      scope: scope,
      action: .link,
      body: () async {
        final identity = state.value?.identity;
        final forge = identity == null
            ? null
            : _registry.forProvider(identity.provider);
        if (identity == null || forge == null) {
          throw const _ActionError('No hosting provider is configured.');
        }
        final number = parseReviewReference(reference);
        if (number == null) {
          throw const _ActionError('Enter a PR number (#123) or URL.');
        }
        final review = await forge.getReviewByNumber(
          identity: identity,
          repoPath: scope.repoPath,
          number: number,
        );
        if (review == null) {
          throw _ActionError('No pull request #$number was found.');
        }
        await _linkedReviews.save(
          .linked(
            workspaceId: scope.workspaceId,
            provider: identity.provider,
            number: number,
            url: review.url,
          ),
        );
      },
    );
  }

  /// Unlinks the review and suppresses auto-detection of that exact review.
  Future<void> unlink() {
    return _run(
      scope: scope,
      action: .unlink,
      body: () async {
        final review = state.value?.review;
        if (review == null) {
          throw const _ActionError('No linked pull request to unlink.');
        }
        await _linkedReviews.save(
          .dismissal(
            workspaceId: scope.workspaceId,
            provider: review.provider,
            number: review.number,
            url: review.url,
          ),
        );
      },
    );
  }

  void _refreshWorkspacePullRequestMonitor() {
    ref
        .read(workspacePullRequestRefreshSignalProvider.notifier)
        .requestRefresh();
  }

  /// Clears the in-flight action; a non-null [failureMessage] surfaces it.
  void _applyActionOutcome({String? failureMessage}) {
    if (_disposed) {
      return;
    }
    final current = state.value ?? const WorkspacePullRequestState();
    state = AsyncData(
      current.copyWith(
        clearAction: true,
        errorMessage: failureMessage,
        clearError: failureMessage == null,
      ),
    );
    _schedulePoll(scope);
  }

  WorkspacePullRequestState _applyPendingCommentBodies(
    WorkspacePullRequestState loaded,
  ) {
    if (_pendingCommentSaves.isEmpty) {
      return loaded;
    }
    final currentComments = state.value?.comments ?? const <ReviewComment>[];
    final loadedIds = loaded.comments.map((comment) => comment.id).toSet();
    final settledIds = <String>{};
    for (final comment in loaded.comments) {
      final pending = _pendingCommentSaves[comment.id];
      if (pending != null &&
          !_savingCommentIds.contains(comment.id) &&
          comment.body == pending.optimisticBody) {
        settledIds.add(comment.id);
      }
    }
    for (final commentId in settledIds) {
      _pendingCommentSaves.remove(commentId);
    }
    final comments = <ReviewComment>[
      for (final comment in loaded.comments)
        _pendingCommentSaves[comment.id] == null
            ? comment
            : comment.copyWith(
                body: _pendingCommentSaves[comment.id]!.optimisticBody,
              ),
      for (final comment in currentComments)
        if (!loadedIds.contains(comment.id) &&
            _pendingCommentSaves.containsKey(comment.id))
          comment.copyWith(
            body: _pendingCommentSaves[comment.id]!.optimisticBody,
          ),
    ];
    return loaded.copyWith(
      comments: comments,
      savingCommentIds: <String>{
        ...loaded.savingCommentIds,
        ..._savingCommentIds,
      },
    );
  }

  /// Runs an action that mutates persisted state, then reloads.
  Future<void> _run({
    required WorkspacePullRequestScope scope,
    required PullRequestAction action,
    required Future<void> Function() body,
    bool reloadAfterFailure = false,
  }) async {
    _pollTimer?.cancel();
    final current = state.value ?? const WorkspacePullRequestState();
    state = AsyncData(current.copyWith(action: action, clearError: true));
    try {
      await body();
      final reloaded = await _loader.load(scope);
      if (!_disposed) {
        state = AsyncData(_applyPendingCommentBodies(reloaded));
        _resetPollInterval();
        _refreshWorkspacePullRequestMonitor();
      }
    } on _ActionError catch (error) {
      await _recordActionFailure(
        scope: scope,
        previous: current,
        message: error.message,
        reload: reloadAfterFailure,
      );
    } on ForgeException catch (error) {
      await _recordActionFailure(
        scope: scope,
        previous: current,
        message: error.message,
        reload: reloadAfterFailure,
      );
    } on GitException catch (error) {
      await _recordActionFailure(
        scope: scope,
        previous: current,
        message: error.context,
        reload: reloadAfterFailure,
      );
    } catch (error) {
      await _recordActionFailure(
        scope: scope,
        previous: current,
        message: error.toString(),
        reload: reloadAfterFailure,
      );
    }
    _schedulePoll(scope);
  }

  Future<void> _recordActionFailure({
    required WorkspacePullRequestScope scope,
    required WorkspacePullRequestState previous,
    required String message,
    required bool reload,
  }) async {
    if (_disposed) {
      return;
    }
    if (reload) {
      try {
        final reloaded = await _loader.load(scope);
        if (!_disposed) {
          state = AsyncData(
            _applyPendingCommentBodies(reloaded)
                .copyWith(clearAction: true, errorMessage: message),
          );
          _resetPollInterval();
          return;
        }
      } catch (_) {
        // Preserve the previous snapshot when the recovery reload also fails.
      }
    }
    if (!_disposed) {
      state = AsyncData(
        (state.value ?? previous).copyWith(
          clearAction: true,
          errorMessage: message,
        ),
      );
    }
  }

  Future<void> _refresh({required _RefreshOrigin origin}) {
    if (_disposed || !_visible) {
      return Future<void>.value();
    }
    final current = state.value;
    if (current == null ||
        (current.isBusy && current.action != PullRequestAction.refresh)) {
      return Future<void>.value();
    }
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final operation = _performRefresh(current: current, origin: origin);
    _refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _performRefresh({
    required WorkspacePullRequestState current,
    required _RefreshOrigin origin,
  }) async {
    _pollTimer?.cancel();
    if (origin != _RefreshOrigin.poll) {
      _resetPollInterval();
    }
    state = AsyncData(current.copyWith(action: .refresh, clearError: true));

    try {
      final reloaded = await _loader.load(scope);
      if (_disposed) {
        return;
      }
      final failed = reloaded.errorMessage != null;
      final visibleReload = _applyPendingCommentBodies(reloaded);
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
      if (!_disposed) {
        state = AsyncData(
          current.copyWith(clearAction: true, errorMessage: error.toString()),
        );
        if (origin == _RefreshOrigin.poll) {
          _advancePollInterval(changed: false);
        }
      }
    } finally {
      _schedulePoll(scope);
    }
  }

  void _resetPollInterval() => _pollInterval = _minPollInterval;

  void _advancePollInterval({required bool changed}) {
    if (changed) {
      _resetPollInterval();
      return;
    }
    final doubled = _pollInterval * 2;
    _pollInterval = doubled > _maxPollInterval ? _maxPollInterval : doubled;
  }

  void _schedulePoll(
    WorkspacePullRequestScope scope, {
    WorkspacePullRequestState? snapshot,
  }) {
    _pollTimer?.cancel();
    final current = snapshot ?? state.value;
    if (_disposed || !_visible || current == null || current.isBusy) {
      return;
    }
    // Missing identity or auth can heal outside the app (the user signs in,
    // adds a remote); keep polling slowly instead of never retrying.
    final degraded =
        current.identity == null ||
        current.authStatus != ForgeAuthStatus.authenticated;
    _pollTimer = Timer(degraded ? _maxPollInterval : _pollInterval, () {
      unawaited(_pollTick(scope));
    });
  }

  Future<void> _pollTick(WorkspacePullRequestScope scope) async {
    _pollTimer = null;
    await _refresh(origin: .poll);
  }
}

enum _RefreshOrigin { manual, poll, resume }

class const _ActionError(final String message) implements Exception;

class const _PendingReviewCommentSave({
  required final String originalBody,
  required final String optimisticBody,
});
