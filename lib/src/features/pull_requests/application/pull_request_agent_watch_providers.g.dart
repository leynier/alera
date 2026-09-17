// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_agent_watch_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PullRequestAgentWatchController)
final pullRequestAgentWatchControllerProvider =
    PullRequestAgentWatchControllerProvider._();

final class PullRequestAgentWatchControllerProvider
    extends
        $NotifierProvider<
          PullRequestAgentWatchController,
          Map<String, PullRequestAgentWatchSession>
        > {
  PullRequestAgentWatchControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pullRequestAgentWatchControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pullRequestAgentWatchControllerHash();

  @$internal
  @override
  PullRequestAgentWatchController create() => PullRequestAgentWatchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, PullRequestAgentWatchSession> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Map<String, PullRequestAgentWatchSession>>(value),
    );
  }
}

String _$pullRequestAgentWatchControllerHash() =>
    r'b9651fca78629a5cfa405a127a8ed25b0c04e6d5';

abstract class _$PullRequestAgentWatchController
    extends $Notifier<Map<String, PullRequestAgentWatchSession>> {
  Map<String, PullRequestAgentWatchSession> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, PullRequestAgentWatchSession>,
              Map<String, PullRequestAgentWatchSession>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, PullRequestAgentWatchSession>,
                Map<String, PullRequestAgentWatchSession>
              >,
              Map<String, PullRequestAgentWatchSession>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
