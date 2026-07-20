// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HostSettingsController)
final hostSettingsControllerProvider = HostSettingsControllerFamily._();

final class HostSettingsControllerProvider
    extends
        $AsyncNotifierProvider<HostSettingsController, PortableHostSettings> {
  HostSettingsControllerProvider._({
    required HostSettingsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hostSettingsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hostSettingsControllerHash();

  @override
  String toString() {
    return r'hostSettingsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HostSettingsController create() => HostSettingsController();

  @override
  bool operator ==(Object other) {
    return other is HostSettingsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hostSettingsControllerHash() =>
    r'3c4037ca0904d136743536821decac13bd30ce57';

final class HostSettingsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          HostSettingsController,
          AsyncValue<PortableHostSettings>,
          PortableHostSettings,
          FutureOr<PortableHostSettings>,
          String
        > {
  HostSettingsControllerFamily._()
    : super(
        retry: null,
        name: r'hostSettingsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  HostSettingsControllerProvider call(String hostId) =>
      HostSettingsControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'hostSettingsControllerProvider';
}

abstract class _$HostSettingsController
    extends $AsyncNotifier<PortableHostSettings> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<PortableHostSettings> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<PortableHostSettings>, PortableHostSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<PortableHostSettings>,
                PortableHostSettings
              >,
              AsyncValue<PortableHostSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
