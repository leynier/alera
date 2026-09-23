// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_agent_watch_scope_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Last Watch and Fix problems chosen on this phone, remembered like desktop
/// settings so the next watch opens with the same checks/comments/conflicts.

@ProviderFor(PullRequestAgentWatchScopeController)
final pullRequestAgentWatchScopeControllerProvider =
    PullRequestAgentWatchScopeControllerProvider._();

/// Last Watch and Fix problems chosen on this phone, remembered like desktop
/// settings so the next watch opens with the same checks/comments/conflicts.
final class PullRequestAgentWatchScopeControllerProvider
    extends
        $AsyncNotifierProvider<
          PullRequestAgentWatchScopeController,
          PullRequestAgentWatchScope
        > {
  /// Last Watch and Fix problems chosen on this phone, remembered like desktop
  /// settings so the next watch opens with the same checks/comments/conflicts.
  PullRequestAgentWatchScopeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pullRequestAgentWatchScopeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$pullRequestAgentWatchScopeControllerHash();

  @$internal
  @override
  PullRequestAgentWatchScopeController create() =>
      PullRequestAgentWatchScopeController();
}

String _$pullRequestAgentWatchScopeControllerHash() =>
    r'20429da44f77e08966096228538b9c3b9a7c5b78';

/// Last Watch and Fix problems chosen on this phone, remembered like desktop
/// settings so the next watch opens with the same checks/comments/conflicts.

abstract class _$PullRequestAgentWatchScopeController
    extends $AsyncNotifier<PullRequestAgentWatchScope> {
  FutureOr<PullRequestAgentWatchScope> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<PullRequestAgentWatchScope>,
              PullRequestAgentWatchScope
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<PullRequestAgentWatchScope>,
                PullRequestAgentWatchScope
              >,
              AsyncValue<PullRequestAgentWatchScope>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
