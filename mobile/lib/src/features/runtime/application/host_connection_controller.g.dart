// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_connection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed, and disposed together
/// with the provider so leaving the host screens tears the socket down.

@ProviderFor(HostConnectionController)
final hostConnectionControllerProvider = HostConnectionControllerFamily._();

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed, and disposed together
/// with the provider so leaving the host screens tears the socket down.
final class HostConnectionControllerProvider
    extends
        $AsyncNotifierProvider<HostConnectionController, MobileRuntimeClient> {
  /// Owns the WebSocket connection to one paired runtime host. The client is
  /// connected and authenticated before it is exposed, and disposed together
  /// with the provider so leaving the host screens tears the socket down.
  HostConnectionControllerProvider._({
    required HostConnectionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hostConnectionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hostConnectionControllerHash();

  @override
  String toString() {
    return r'hostConnectionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HostConnectionController create() => HostConnectionController();

  @override
  bool operator ==(Object other) {
    return other is HostConnectionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hostConnectionControllerHash() =>
    r'63a5ce5f4728a9451cf4d7802b7c69343cec3bcd';

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed, and disposed together
/// with the provider so leaving the host screens tears the socket down.

final class HostConnectionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          HostConnectionController,
          AsyncValue<MobileRuntimeClient>,
          MobileRuntimeClient,
          FutureOr<MobileRuntimeClient>,
          String
        > {
  HostConnectionControllerFamily._()
    : super(
        retry: null,
        name: r'hostConnectionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Owns the WebSocket connection to one paired runtime host. The client is
  /// connected and authenticated before it is exposed, and disposed together
  /// with the provider so leaving the host screens tears the socket down.

  HostConnectionControllerProvider call(String hostId) =>
      HostConnectionControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostConnectionControllerProvider';
}

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed, and disposed together
/// with the provider so leaving the host screens tears the socket down.

abstract class _$HostConnectionController
    extends $AsyncNotifier<MobileRuntimeClient> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<MobileRuntimeClient> build(String hostId);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}
