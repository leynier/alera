// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_connection_probe.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Re-checks one host's socket when the app comes back to the foreground.
///
/// Mobile platforms suspend sockets in the background, and a NAT-idled
/// half-open TCP connection never surfaces an error on its own, so a client
/// that still looks live can be dead. One cheap round trip tells them apart.

@ProviderFor(HostConnectionProbe)
final hostConnectionProbeProvider = HostConnectionProbeFamily._();

/// Re-checks one host's socket when the app comes back to the foreground.
///
/// Mobile platforms suspend sockets in the background, and a NAT-idled
/// half-open TCP connection never surfaces an error on its own, so a client
/// that still looks live can be dead. One cheap round trip tells them apart.
final class HostConnectionProbeProvider
    extends $NotifierProvider<HostConnectionProbe, void> {
  /// Re-checks one host's socket when the app comes back to the foreground.
  ///
  /// Mobile platforms suspend sockets in the background, and a NAT-idled
  /// half-open TCP connection never surfaces an error on its own, so a client
  /// that still looks live can be dead. One cheap round trip tells them apart.
  HostConnectionProbeProvider._({
    required HostConnectionProbeFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hostConnectionProbeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hostConnectionProbeHash();

  @override
  String toString() {
    return r'hostConnectionProbeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HostConnectionProbe create() => HostConnectionProbe();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostConnectionProbeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hostConnectionProbeHash() =>
    r'7ee43b89257ca1f60fc6a1085747299682c387ba';

/// Re-checks one host's socket when the app comes back to the foreground.
///
/// Mobile platforms suspend sockets in the background, and a NAT-idled
/// half-open TCP connection never surfaces an error on its own, so a client
/// that still looks live can be dead. One cheap round trip tells them apart.

final class HostConnectionProbeFamily extends $Family
    with $ClassFamilyOverride<HostConnectionProbe, void, void, void, String> {
  HostConnectionProbeFamily._()
    : super(
        retry: null,
        name: r'hostConnectionProbeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Re-checks one host's socket when the app comes back to the foreground.
  ///
  /// Mobile platforms suspend sockets in the background, and a NAT-idled
  /// half-open TCP connection never surfaces an error on its own, so a client
  /// that still looks live can be dead. One cheap round trip tells them apart.

  HostConnectionProbeProvider call(String hostId) =>
      HostConnectionProbeProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostConnectionProbeProvider';
}

/// Re-checks one host's socket when the app comes back to the foreground.
///
/// Mobile platforms suspend sockets in the background, and a NAT-idled
/// half-open TCP connection never surfaces an error on its own, so a client
/// that still looks live can be dead. One cheap round trip tells them apart.

abstract class _$HostConnectionProbe extends $Notifier<void> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  void build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
