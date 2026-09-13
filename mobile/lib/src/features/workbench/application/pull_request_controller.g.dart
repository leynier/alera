// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PullRequestController)
final pullRequestControllerProvider = PullRequestControllerFamily._();

final class PullRequestControllerProvider
    extends
        $AsyncNotifierProvider<
          PullRequestController,
          MobilePullRequestSnapshot
        > {
  PullRequestControllerProvider._({
    required PullRequestControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pullRequestControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pullRequestControllerHash();

  @override
  String toString() {
    return r'pullRequestControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PullRequestController create() => PullRequestController();

  @override
  bool operator ==(Object other) {
    return other is PullRequestControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pullRequestControllerHash() =>
    r'2065b272a6c8fc5be1c79d04215f2c64f2fb9314';

final class PullRequestControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PullRequestController,
          AsyncValue<MobilePullRequestSnapshot>,
          MobilePullRequestSnapshot,
          FutureOr<MobilePullRequestSnapshot>,
          (String, String)
        > {
  PullRequestControllerFamily._()
    : super(
        retry: null,
        name: r'pullRequestControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PullRequestControllerProvider call(String hostId, String workspaceId) =>
      PullRequestControllerProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'pullRequestControllerProvider';
}

abstract class _$PullRequestController
    extends $AsyncNotifier<MobilePullRequestSnapshot> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  FutureOr<MobilePullRequestSnapshot> build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<MobilePullRequestSnapshot>,
              MobilePullRequestSnapshot
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<MobilePullRequestSnapshot>,
                MobilePullRequestSnapshot
              >,
              AsyncValue<MobilePullRequestSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
