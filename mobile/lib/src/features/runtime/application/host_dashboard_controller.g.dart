// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_dashboard_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(hostDashboardData)
final hostDashboardDataProvider = HostDashboardDataFamily._();

final class HostDashboardDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<HostDashboardData>,
          HostDashboardData,
          FutureOr<HostDashboardData>
        >
    with
        $FutureModifier<HostDashboardData>,
        $FutureProvider<HostDashboardData> {
  HostDashboardDataProvider._({
    required HostDashboardDataFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hostDashboardDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hostDashboardDataHash();

  @override
  String toString() {
    return r'hostDashboardDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<HostDashboardData> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HostDashboardData> create(Ref ref) {
    final argument = this.argument as String;
    return hostDashboardData(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is HostDashboardDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hostDashboardDataHash() => r'ed53eb39eb232e14f0373a5fcc95628fa3734cd5';

final class HostDashboardDataFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<HostDashboardData>, String> {
  HostDashboardDataFamily._()
    : super(
        retry: null,
        name: r'hostDashboardDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  HostDashboardDataProvider call(String hostId) =>
      HostDashboardDataProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostDashboardDataProvider';
}
