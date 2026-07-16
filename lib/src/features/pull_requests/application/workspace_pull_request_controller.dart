import 'dart:async';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/review_reference_parser.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_loader.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_controller.g.dart';
part 'workspace_pull_request_review_actions.dart';

@Riverpod(keepAlive: true)
class WorkspacePullRequestController extends _$WorkspacePullRequestController
    with _WorkspacePullRequestReviewActions {
  static const Duration _minPollInterval = Duration(seconds: 30);
  static const Duration _maxPollInterval = Duration(seconds: 120);

  late final GitBackend _gitBackend;
  late final ForgeProviderRegistry _registry;
  late final LinkedReviewRepository _linkedReviews;
  late final WorkspacePullRequestLoader _loader;

  Timer? _pollTimer;
  Duration _pollInterval = _minPollInterval;
  Future<void>? _refreshInFlight;
  var _panelViewCount = 0;
  bool _visible = false;
  bool _disposed = false;

  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async {
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
    });
    final initial = await _loader.load(scope);
    _schedulePoll(scope, snapshot: initial);
    return initial;
  }

  /// Reloads review + checks now.
  Future<void> refresh() => _refresh(origin: _RefreshOrigin.manual);

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
          unawaited(_refresh(origin: _RefreshOrigin.resume));
        }
      });
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
      action: PullRequestAction.link,
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
          LinkedReview.linked(
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
      action: PullRequestAction.unlink,
      body: () async {
        final review = state.value?.review;
        if (review == null) {
          throw const _ActionError('No linked pull request to unlink.');
        }
        await _linkedReviews.save(
          LinkedReview.dismissal(
            workspaceId: scope.workspaceId,
            provider: review.provider,
            number: review.number,
            url: review.url,
          ),
        );
      },
    );
  }

  /// Creates a review from [input]: pushes the branch, calls the forge, and
  /// links the result on success.
  Future<CreateReviewResult> createReview(CreateReviewInput input) async {
    final identity = state.value?.identity;
    final forge = identity == null
        ? null
        : _registry.forProvider(identity.provider);
    if (identity == null || forge == null) {
      return const CreateReviewFailure(
        code: CreateReviewErrorCode.blocked,
        message: 'No hosting provider is configured.',
      );
    }
    _pollTimer?.cancel();
    state = AsyncData(
      (state.value ?? const WorkspacePullRequestState()).copyWith(
        action: PullRequestAction.create,
        clearError: true,
      ),
    );
    try {
      await _gitBackend.push(scope.repoPath);
    } on GitException catch (error) {
      final result = CreateReviewFailure(
        code: CreateReviewErrorCode.pushFailed,
        message: 'Could not push the branch: ${error.context}',
      );
      _applyActionOutcome(failureMessage: result.message);
      return result;
    }
    final result = await forge.createReview(
      identity: identity,
      repoPath: scope.repoPath,
      input: input,
    );
    if (result is CreateReviewSuccess) {
      await _linkedReviews.save(
        LinkedReview.linked(
          workspaceId: scope.workspaceId,
          provider: identity.provider,
          number: result.review.number,
          url: result.review.url,
        ),
      );
    }
    _applyActionOutcome(
      failureMessage: result is CreateReviewFailure ? result.message : null,
    );
    if (!_disposed && _visible) {
      await refresh();
    }
    return result;
  }

  /// Detail metadata for [check] of the linked review; null when nothing is
  /// linked or the check is gone. Transport/auth failures throw.
  Future<ReviewCheckDetails?> loadCheckDetails(ReviewCheck check) async {
    final current = state.value;
    final identity = current?.identity;
    final review = current?.review;
    final forge = identity == null
        ? null
        : _registry.forProvider(identity.provider);
    if (identity == null || review == null || forge == null) {
      return null;
    }
    return forge.getCheckDetails(
      identity: identity,
      repoPath: scope.repoPath,
      number: review.number,
      check: check,
    );
  }

  /// Updates the linked review from [input], then reloads.
  Future<UpdateReviewResult> updateReview(UpdateReviewInput input) async {
    final identity = state.value?.identity;
    final review = state.value?.review;
    final forge = identity == null
        ? null
        : _registry.forProvider(identity.provider);
    if (identity == null || review == null || forge == null) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.blocked,
        message: 'No linked pull request to update.',
      );
    }
    if (input.isEmpty) {
      return const UpdateReviewFailure(
        code: UpdateReviewErrorCode.blocked,
        message: 'Nothing to update.',
      );
    }
    _pollTimer?.cancel();
    state = AsyncData(
      (state.value ?? const WorkspacePullRequestState()).copyWith(
        action: PullRequestAction.update,
        clearError: true,
      ),
    );
    final result = await forge.updateReview(
      identity: identity,
      repoPath: scope.repoPath,
      number: review.number,
      input: input,
    );
    _applyActionOutcome(
      failureMessage: result is UpdateReviewFailure ? result.message : null,
    );
    // Reload only on success; the refresh path would clear the error message.
    if (!_disposed && _visible && result is UpdateReviewSuccess) {
      await refresh();
    }
    return result;
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

  /// Runs an action that mutates persisted state, then reloads.
  Future<void> _run({
    required WorkspacePullRequestScope scope,
    required PullRequestAction action,
    required Future<void> Function() body,
  }) async {
    _pollTimer?.cancel();
    final current = state.value ?? const WorkspacePullRequestState();
    state = AsyncData(current.copyWith(action: action, clearError: true));
    try {
      await body();
      final reloaded = await _loader.load(scope);
      if (!_disposed) {
        state = AsyncData(reloaded);
        _resetPollInterval();
      }
    } on _ActionError catch (error) {
      if (!_disposed) {
        state = AsyncData(
          (state.value ?? current).copyWith(
            clearAction: true,
            errorMessage: error.message,
          ),
        );
      }
    } on ForgeException catch (error) {
      if (!_disposed) {
        state = AsyncData(
          (state.value ?? current).copyWith(
            clearAction: true,
            errorMessage: error.message,
          ),
        );
      }
    } catch (error) {
      if (!_disposed) {
        state = AsyncData(
          (state.value ?? current).copyWith(
            clearAction: true,
            errorMessage: error.toString(),
          ),
        );
      }
    }
    _schedulePoll(scope);
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
    state = AsyncData(
      current.copyWith(action: PullRequestAction.refresh, clearError: true),
    );

    try {
      final reloaded = await _loader.load(scope);
      if (_disposed) {
        return;
      }
      final failed = reloaded.errorMessage != null;
      state = AsyncData(
        failed
            ? current.copyWith(
                clearAction: true,
                errorMessage: reloaded.errorMessage,
              )
            : reloaded,
      );
      if (origin == _RefreshOrigin.poll) {
        _advancePollInterval(
          changed: !failed && reloaded.pollSignature != current.pollSignature,
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
    if (_disposed ||
        !_visible ||
        current == null ||
        current.isBusy ||
        current.identity == null ||
        current.authStatus != ForgeAuthStatus.authenticated) {
      return;
    }
    _pollTimer = Timer(_pollInterval, () {
      unawaited(_pollTick(scope));
    });
  }

  Future<void> _pollTick(WorkspacePullRequestScope scope) async {
    _pollTimer = null;
    await _refresh(origin: _RefreshOrigin.poll);
  }
}

enum _RefreshOrigin { manual, poll, resume }

class _ActionError implements Exception {
  const _ActionError(this.message);

  final String message;
}
