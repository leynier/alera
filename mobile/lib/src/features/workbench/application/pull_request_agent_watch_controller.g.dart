// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_agent_watch_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Client-side Watch and Fix for one workspace. `keepAlive` so leaving the
/// Pull Request panel does not drop the session; polling pauses while the app
/// is backgrounded and resumes with the next snapshot.

@ProviderFor(PullRequestAgentWatchController)
final pullRequestAgentWatchControllerProvider =
    PullRequestAgentWatchControllerFamily._();

/// Client-side Watch and Fix for one workspace. `keepAlive` so leaving the
/// Pull Request panel does not drop the session; polling pauses while the app
/// is backgrounded and resumes with the next snapshot.
final class PullRequestAgentWatchControllerProvider
    extends
        $NotifierProvider<
          PullRequestAgentWatchController,
          PullRequestAgentWatchSession?
        > {
  /// Client-side Watch and Fix for one workspace. `keepAlive` so leaving the
  /// Pull Request panel does not drop the session; polling pauses while the app
  /// is backgrounded and resumes with the next snapshot.
  PullRequestAgentWatchControllerProvider._({
    required PullRequestAgentWatchControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pullRequestAgentWatchControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pullRequestAgentWatchControllerHash();

  @override
  String toString() {
    return r'pullRequestAgentWatchControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PullRequestAgentWatchController create() => PullRequestAgentWatchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PullRequestAgentWatchSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PullRequestAgentWatchSession?>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PullRequestAgentWatchControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pullRequestAgentWatchControllerHash() =>
    r'48109511fdc86817bf87b8e2ebc3e4b3eb92ad69';

/// Client-side Watch and Fix for one workspace. `keepAlive` so leaving the
/// Pull Request panel does not drop the session; polling pauses while the app
/// is backgrounded and resumes with the next snapshot.

final class PullRequestAgentWatchControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PullRequestAgentWatchController,
          PullRequestAgentWatchSession?,
          PullRequestAgentWatchSession?,
          PullRequestAgentWatchSession?,
          (String, String)
        > {
  PullRequestAgentWatchControllerFamily._()
    : super(
        retry: null,
        name: r'pullRequestAgentWatchControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Client-side Watch and Fix for one workspace. `keepAlive` so leaving the
  /// Pull Request panel does not drop the session; polling pauses while the app
  /// is backgrounded and resumes with the next snapshot.

  PullRequestAgentWatchControllerProvider call(
    String hostId,
    String workspaceId,
  ) => PullRequestAgentWatchControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'pullRequestAgentWatchControllerProvider';
}

/// Client-side Watch and Fix for one workspace. `keepAlive` so leaving the
/// Pull Request panel does not drop the session; polling pauses while the app
/// is backgrounded and resumes with the next snapshot.

abstract class _$PullRequestAgentWatchController
    extends $Notifier<PullRequestAgentWatchSession?> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  PullRequestAgentWatchSession? build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              PullRequestAgentWatchSession?,
              PullRequestAgentWatchSession?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                PullRequestAgentWatchSession?,
                PullRequestAgentWatchSession?
              >,
              PullRequestAgentWatchSession?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
