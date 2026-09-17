// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_agent_watch_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(pullRequestAgentWatchRepository)
final pullRequestAgentWatchRepositoryProvider =
    PullRequestAgentWatchRepositoryProvider._();

final class PullRequestAgentWatchRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimePullRequestWatchRepository,
          RuntimePullRequestWatchRepository,
          RuntimePullRequestWatchRepository
        >
    with $Provider<RuntimePullRequestWatchRepository> {
  PullRequestAgentWatchRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pullRequestAgentWatchRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pullRequestAgentWatchRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimePullRequestWatchRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimePullRequestWatchRepository create(Ref ref) {
    return pullRequestAgentWatchRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimePullRequestWatchRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimePullRequestWatchRepository>(
        value,
      ),
    );
  }
}

String _$pullRequestAgentWatchRepositoryHash() =>
    r'a588b23bd4f34e2c09252df150b788cb5a591d4a';

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
    r'54d2e10dc14270699baae36fdeb13a73bed78289';

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
