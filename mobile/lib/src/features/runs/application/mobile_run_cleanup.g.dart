// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_run_cleanup.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MobileRunResources)
final mobileRunResourcesProvider = MobileRunResourcesFamily._();

final class MobileRunResourcesProvider
    extends $AsyncNotifierProvider<MobileRunResources, RunResourcesSnapshot> {
  MobileRunResourcesProvider._({
    required MobileRunResourcesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunResourcesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunResourcesHash();

  @override
  String toString() {
    return r'mobileRunResourcesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunResources create() => MobileRunResources();

  @override
  bool operator ==(Object other) {
    return other is MobileRunResourcesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunResourcesHash() =>
    r'ee9385644d5c9b6c06eeeb074186e1e91449b9be';

final class MobileRunResourcesFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunResources,
          AsyncValue<RunResourcesSnapshot>,
          RunResourcesSnapshot,
          FutureOr<RunResourcesSnapshot>,
          (String, String)
        > {
  MobileRunResourcesFamily._()
    : super(
        retry: null,
        name: r'mobileRunResourcesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileRunResourcesProvider call(String hostId, String runId) =>
      MobileRunResourcesProvider._(argument: (hostId, runId), from: this);

  @override
  String toString() => r'mobileRunResourcesProvider';
}

abstract class _$MobileRunResources
    extends $AsyncNotifier<RunResourcesSnapshot> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get runId => _$args.$2;

  FutureOr<RunResourcesSnapshot> build(String hostId, String runId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<RunResourcesSnapshot>, RunResourcesSnapshot>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunResourcesSnapshot>,
                RunResourcesSnapshot
              >,
              AsyncValue<RunResourcesSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

@ProviderFor(MobileRunCleanup)
final mobileRunCleanupProvider = MobileRunCleanupFamily._();

final class MobileRunCleanupProvider
    extends $NotifierProvider<MobileRunCleanup, RunCleanupDraft> {
  MobileRunCleanupProvider._({
    required MobileRunCleanupFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunCleanupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunCleanupHash();

  @override
  String toString() {
    return r'mobileRunCleanupProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunCleanup create() => MobileRunCleanup();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunCleanupDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunCleanupDraft>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunCleanupProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunCleanupHash() => r'fd41eb0002225a70b69301836272f99197421236';

final class MobileRunCleanupFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunCleanup,
          RunCleanupDraft,
          RunCleanupDraft,
          RunCleanupDraft,
          (String, String)
        > {
  MobileRunCleanupFamily._()
    : super(
        retry: null,
        name: r'mobileRunCleanupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileRunCleanupProvider call(String hostId, String runId) =>
      MobileRunCleanupProvider._(argument: (hostId, runId), from: this);

  @override
  String toString() => r'mobileRunCleanupProvider';
}

abstract class _$MobileRunCleanup extends $Notifier<RunCleanupDraft> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get runId => _$args.$2;

  RunCleanupDraft build(String hostId, String runId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RunCleanupDraft, RunCleanupDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RunCleanupDraft, RunCleanupDraft>,
              RunCleanupDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
