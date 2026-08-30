// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_connection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed. Transport failures recover
/// while the app is in the foreground, and leaving every host surface disposes
/// the client and stops retry work.

@ProviderFor(HostConnectionController)
final hostConnectionControllerProvider = HostConnectionControllerFamily._();

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed. Transport failures recover
/// while the app is in the foreground, and leaving every host surface disposes
/// the client and stops retry work.
final class HostConnectionControllerProvider
    extends
        $AsyncNotifierProvider<HostConnectionController, MobileRuntimeClient> {
  /// Owns the WebSocket connection to one paired runtime host. The client is
  /// connected and authenticated before it is exposed. Transport failures recover
  /// while the app is in the foreground, and leaving every host surface disposes
  /// the client and stops retry work.
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
    r'bed5032ce09bdeb60cf8c887f15059eb0aa82ec5';

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed. Transport failures recover
/// while the app is in the foreground, and leaving every host surface disposes
/// the client and stops retry work.

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
  /// connected and authenticated before it is exposed. Transport failures recover
  /// while the app is in the foreground, and leaving every host surface disposes
  /// the client and stops retry work.

  HostConnectionControllerProvider call(String hostId) =>
      HostConnectionControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostConnectionControllerProvider';
}

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed. Transport failures recover
/// while the app is in the foreground, and leaving every host surface disposes
/// the client and stops retry work.

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
