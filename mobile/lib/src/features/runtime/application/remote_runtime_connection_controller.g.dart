// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_runtime_connection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RemoteRuntimeConnectionController)
final remoteRuntimeConnectionControllerProvider =
    RemoteRuntimeConnectionControllerFamily._();

final class RemoteRuntimeConnectionControllerProvider
    extends
        $AsyncNotifierProvider<
          RemoteRuntimeConnectionController,
          MobileRuntimeClient
        > {
  RemoteRuntimeConnectionControllerProvider._({
    required RemoteRuntimeConnectionControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'remoteRuntimeConnectionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$remoteRuntimeConnectionControllerHash();

  @override
  String toString() {
    return r'remoteRuntimeConnectionControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RemoteRuntimeConnectionController create() =>
      RemoteRuntimeConnectionController();

  @override
  bool operator ==(Object other) {
    return other is RemoteRuntimeConnectionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$remoteRuntimeConnectionControllerHash() =>
    r'3348911f234ffb02491b62ff7bd32f5c5a13605d';

final class RemoteRuntimeConnectionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          RemoteRuntimeConnectionController,
          AsyncValue<MobileRuntimeClient>,
          MobileRuntimeClient,
          FutureOr<MobileRuntimeClient>,
          (String, String)
        > {
  RemoteRuntimeConnectionControllerFamily._()
    : super(
        retry: null,
        name: r'remoteRuntimeConnectionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RemoteRuntimeConnectionControllerProvider call(
    String accountId,
    String runtimeId,
  ) => RemoteRuntimeConnectionControllerProvider._(
    argument: (accountId, runtimeId),
    from: this,
  );

  @override
  String toString() => r'remoteRuntimeConnectionControllerProvider';
}

abstract class _$RemoteRuntimeConnectionController
    extends $AsyncNotifier<MobileRuntimeClient> {
  late final _$args = ref.$arg as (String, String);
  String get accountId => _$args.$1;
  String get runtimeId => _$args.$2;

  FutureOr<MobileRuntimeClient> build(String accountId, String runtimeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<MobileRuntimeClient>, MobileRuntimeClient>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MobileRuntimeClient>, MobileRuntimeClient>,
              AsyncValue<MobileRuntimeClient>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
