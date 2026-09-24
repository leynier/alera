// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_watch_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.

@ProviderFor(PullRequestWatchController)
final pullRequestWatchControllerProvider = PullRequestWatchControllerFamily._();

/// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.
final class PullRequestWatchControllerProvider
    extends
        $AsyncNotifierProvider<
          PullRequestWatchController,
          MobilePullRequestWatchSnapshot
        > {
  /// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.
  PullRequestWatchControllerProvider._({
    required PullRequestWatchControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pullRequestWatchControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pullRequestWatchControllerHash();

  @override
  String toString() {
    return r'pullRequestWatchControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PullRequestWatchController create() => PullRequestWatchController();

  @override
  bool operator ==(Object other) {
    return other is PullRequestWatchControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pullRequestWatchControllerHash() =>
    r'2d5d5533b81dc71d03052cf670bcc2b7605d8761';

/// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.

final class PullRequestWatchControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PullRequestWatchController,
          AsyncValue<MobilePullRequestWatchSnapshot>,
          MobilePullRequestWatchSnapshot,
          FutureOr<MobilePullRequestWatchSnapshot>,
          String
        > {
  PullRequestWatchControllerFamily._()
    : super(
        retry: null,
        name: r'pullRequestWatchControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.

  PullRequestWatchControllerProvider call(String hostId) =>
      PullRequestWatchControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'pullRequestWatchControllerProvider';
}

/// Every Watch and Fix session on one host, refreshed on `pullRequestWatchChanged`.

abstract class _$PullRequestWatchController
    extends $AsyncNotifier<MobilePullRequestWatchSnapshot> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<MobilePullRequestWatchSnapshot> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<MobilePullRequestWatchSnapshot>,
              MobilePullRequestWatchSnapshot
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<MobilePullRequestWatchSnapshot>,
                MobilePullRequestWatchSnapshot
              >,
              AsyncValue<MobilePullRequestWatchSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
