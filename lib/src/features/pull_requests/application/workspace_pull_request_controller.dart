import 'dart:async';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/hosting_provider_resolver.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/review_reference_parser.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_pull_request_controller.g.dart';

/// Why the pull-request panel has no provider to work with.
enum PullRequestUnavailableReason { noRemote, undetectable, unsupported }

/// In-flight action for busy indicators.
enum PullRequestAction { refresh, link, unlink, create }

/// Immutable state of the pull-request panel for one workspace.
class WorkspacePullRequestState {
  const WorkspacePullRequestState({
    this.identity,
    this.unavailableReason,
    this.authStatus = ForgeAuthStatus.unknown,
    this.review,
    this.checks = const <ReviewCheck>[],
    this.linkedManually = false,
    this.dismissed = false,
    this.currentBranch,
    this.action,
    this.errorMessage,
  });

  final GitRemoteIdentity? identity;
  final PullRequestUnavailableReason? unavailableReason;
  final ForgeAuthStatus authStatus;
  final HostedReview? review;
  final List<ReviewCheck> checks;
  final bool linkedManually;
  final bool dismissed;

  /// The current branch of the controlled repository, or null when detached or
  /// unavailable. Drives auto-detection and the create-review head branch.
  final String? currentBranch;

  final PullRequestAction? action;
  final String? errorMessage;

  bool get isBusy => action != null;
  bool get hasReview => review != null;
  bool get providerAvailable => identity != null;
  bool get isAuthenticated => authStatus == ForgeAuthStatus.authenticated;
  bool get supportsCreation =>
      providerAvailable &&
      isAuthenticated &&
      review == null &&
      unavailableReason == null;

  ReviewChecksRollup get checksRollup => deriveReviewChecksRollup(checks);

  WorkspacePullRequestState copyWith({
    GitRemoteIdentity? identity,
    PullRequestUnavailableReason? unavailableReason,
    ForgeAuthStatus? authStatus,
    HostedReview? review,
    List<ReviewCheck>? checks,
    bool? linkedManually,
    bool? dismissed,
    String? currentBranch,
    PullRequestAction? action,
    bool clearAction = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WorkspacePullRequestState(
      identity: identity ?? this.identity,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      authStatus: authStatus ?? this.authStatus,
      review: review ?? this.review,
      checks: checks ?? this.checks,
      linkedManually: linkedManually ?? this.linkedManually,
      dismissed: dismissed ?? this.dismissed,
      currentBranch: currentBranch ?? this.currentBranch,
      action: clearAction ? null : (action ?? this.action),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// A cheap signature of the display-relevant data, used by polling to detect
  /// change and adapt its interval.
  String get pollSignature {
    final checkPart = checks
        .map((c) => '${c.name}:${c.status.name}:${c.conclusion.name}')
        .join('|');
    return '${review?.number}:${review?.state.name}:$checkPart';
  }
}

@riverpod
class WorkspacePullRequestController extends _$WorkspacePullRequestController {
  static const Duration _minPollInterval = Duration(seconds: 30);
  static const Duration _maxPollInterval = Duration(seconds: 120);

  late final GitBackend _gitBackend;
  late final ForgeProviderRegistry _registry;
  late final LinkedReviewRepository _linkedReviews;

  Timer? _pollTimer;
  Duration _pollInterval = _minPollInterval;
  bool _disposed = false;

  @override
  Future<WorkspacePullRequestState> build(WorkspacePullRequestScope scope) async {
    _gitBackend = ref.read(gitBackendProvider);
    _registry = ref.read(forgeProviderRegistryProvider);
    _linkedReviews = ref.read(linkedReviewRepositoryProvider);
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
    });
    final state = await _load(scope);
    _schedulePoll(scope);
    return state;
  }

  /// Reloads review + checks now.
  Future<void> refresh() =>
      _run(scope: scope, action: PullRequestAction.refresh, body: () async {});

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

  /// Unlinks the review; the panel stays empty and auto-detection is suppressed.
  Future<void> unlink() {
    return _run(
      scope: scope,
      action: PullRequestAction.unlink,
      body: () async {
        await _linkedReviews.save(
          LinkedReview.dismissal(workspaceId: scope.workspaceId),
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
      _applyCreateResult(result);
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
    _applyCreateResult(result);
    if (!_disposed) {
      await _run(
        scope: scope,
        action: PullRequestAction.refresh,
        body: () async {},
      );
    }
    return result;
  }

  void _applyCreateResult(CreateReviewResult result) {
    if (_disposed) {
      return;
    }
    final current = state.value ?? const WorkspacePullRequestState();
    state = AsyncData(
      current.copyWith(
        clearAction: true,
        errorMessage: result is CreateReviewFailure ? result.message : null,
        clearError: result is CreateReviewSuccess,
      ),
    );
  }

  /// Runs an action that mutates persisted state, then reloads.
  Future<void> _run({
    required WorkspacePullRequestScope scope,
    required PullRequestAction action,
    required Future<void> Function() body,
  }) async {
    final current = state.value ?? const WorkspacePullRequestState();
    state = AsyncData(current.copyWith(action: action, clearError: true));
    try {
      await body();
      final reloaded = await _load(scope);
      if (!_disposed) {
        state = AsyncData(reloaded);
        _resetPollInterval();
        _schedulePoll(scope);
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
  }

  Future<WorkspacePullRequestState> _load(
    WorkspacePullRequestScope scope,
  ) async {
    final resolution = await _resolveIdentity(scope);
    if (resolution.identity == null) {
      return WorkspacePullRequestState(
        unavailableReason: resolution.reason,
      );
    }
    final identity = resolution.identity!;
    final forge = _registry.forProvider(identity.provider);
    if (forge == null) {
      return WorkspacePullRequestState(
        identity: identity,
        unavailableReason: PullRequestUnavailableReason.unsupported,
      );
    }
    final authStatus = await forge.checkAuth(identity: identity);
    final branch = await _resolveBranch(scope);
    final persisted = await _linkedReviews.find(scope.workspaceId);

    if (persisted != null && persisted.dismissed) {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        currentBranch: branch,
        dismissed: true,
      );
    }
    if (authStatus != ForgeAuthStatus.authenticated) {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        currentBranch: branch,
      );
    }

    final linkedManually = persisted != null && persisted.hasReview;
    try {
      final review = linkedManually
          ? await forge.getReviewByNumber(
              identity: identity,
              repoPath: scope.repoPath,
              number: persisted.number!,
            )
          : await _detectReview(forge, identity, scope, branch);
      final checks = review == null
          ? const <ReviewCheck>[]
          : await forge.getChecks(
              identity: identity,
              repoPath: scope.repoPath,
              number: review.number,
            );
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        review: review,
        checks: checks,
        linkedManually: linkedManually,
        currentBranch: branch,
      );
    } on ForgeNotAuthenticated {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: ForgeAuthStatus.notAuthenticated,
        currentBranch: branch,
      );
    } on ForgeCliMissing {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: ForgeAuthStatus.cliMissing,
        currentBranch: branch,
      );
    } on ForgeException catch (error) {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        currentBranch: branch,
        errorMessage: error.message,
      );
    }
  }

  /// The branch to detect/create against: the scope hint (a git-repository
  /// workspace's branch) when present, otherwise the current branch of the
  /// controlled repository. Null when detached or unavailable.
  Future<String?> _resolveBranch(WorkspacePullRequestScope scope) async {
    final hinted = scope.branch;
    if (hinted != null && hinted.isNotEmpty && hinted != 'HEAD') {
      return hinted;
    }
    try {
      final current = await _gitBackend.currentBranch(scope.repoPath);
      return current.isEmpty || current == 'HEAD' ? null : current;
    } on GitException {
      return null;
    }
  }

  Future<HostedReview?> _detectReview(
    ForgeProvider forge,
    GitRemoteIdentity identity,
    WorkspacePullRequestScope scope,
    String? branch,
  ) async {
    if (branch == null || branch.isEmpty) {
      return null;
    }
    return forge.getReviewForBranch(
      identity: identity,
      repoPath: scope.repoPath,
      branch: branch,
    );
  }

  Future<({GitRemoteIdentity? identity, PullRequestUnavailableReason? reason})>
  _resolveIdentity(WorkspacePullRequestScope scope) async {
    List<GitRemote> remotes;
    try {
      remotes = await _gitBackend.listRemotes(scope.repoPath);
    } on GitException {
      return (identity: null, reason: PullRequestUnavailableReason.noRemote);
    }
    final resolution = resolveHostingProvider(
      remotes: remotes,
      override: scope.providerOverride,
    );
    return switch (resolution) {
      HostingProviderResolved(:final identity) => (
        identity: identity,
        reason: null,
      ),
      HostingProviderUndetectable() => (
        identity: null,
        reason: PullRequestUnavailableReason.undetectable,
      ),
      HostingProviderNoRemote() => (
        identity: null,
        reason: PullRequestUnavailableReason.noRemote,
      ),
    };
  }

  void _resetPollInterval() => _pollInterval = _minPollInterval;

  void _schedulePoll(WorkspacePullRequestScope scope) {
    _pollTimer?.cancel();
    final current = state.value;
    // Only poll when there is a provider to talk to and the user hasn't
    // dismissed the panel. Auto-dispose stops polling when the panel is hidden.
    if (current == null ||
        current.identity == null ||
        current.dismissed ||
        current.authStatus != ForgeAuthStatus.authenticated) {
      return;
    }
    _pollTimer = Timer(_pollInterval, () => _pollTick(scope));
  }

  Future<void> _pollTick(WorkspacePullRequestScope scope) async {
    if (_disposed) {
      return;
    }
    final previous = state.value?.pollSignature;
    final next = await _load(scope);
    if (_disposed) {
      return;
    }
    state = AsyncData(next);
    if (next.pollSignature == previous) {
      _pollInterval = _pollInterval * 2 > _maxPollInterval
          ? _maxPollInterval
          : _pollInterval * 2;
    } else {
      _pollInterval = _minPollInterval;
    }
    _schedulePoll(scope);
  }
}

class _ActionError implements Exception {
  const _ActionError(this.message);

  final String message;
}
