// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_connection_health.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HostConnectionHealthController)
final hostConnectionHealthControllerProvider =
    HostConnectionHealthControllerFamily._();

final class HostConnectionHealthControllerProvider
    extends
        $NotifierProvider<
          HostConnectionHealthController,
          HostConnectionHealth
        > {
  HostConnectionHealthControllerProvider._({
    required HostConnectionHealthControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hostConnectionHealthControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hostConnectionHealthControllerHash();

  @override
  String toString() {
    return r'hostConnectionHealthControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HostConnectionHealthController create() => HostConnectionHealthController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HostConnectionHealth value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HostConnectionHealth>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostConnectionHealthControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hostConnectionHealthControllerHash() =>
    r'a53b4499ec67d2abc6cc14a813aa715d492ae357';

final class HostConnectionHealthControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          HostConnectionHealthController,
          HostConnectionHealth,
          HostConnectionHealth,
          HostConnectionHealth,
          String
        > {
  HostConnectionHealthControllerFamily._()
    : super(
        retry: null,
        name: r'hostConnectionHealthControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  HostConnectionHealthControllerProvider call(String hostId) =>
      HostConnectionHealthControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostConnectionHealthControllerProvider';
}

abstract class _$HostConnectionHealthController
    extends $Notifier<HostConnectionHealth> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  HostConnectionHealth build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HostConnectionHealth, HostConnectionHealth>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HostConnectionHealth, HostConnectionHealth>,
              HostConnectionHealth,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
