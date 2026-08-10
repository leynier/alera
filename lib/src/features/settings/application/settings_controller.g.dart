// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SettingsController)
final settingsControllerProvider = SettingsControllerProvider._();

final class SettingsControllerProvider
    extends $NotifierProvider<SettingsController, AleraSettings> {
  SettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsControllerHash();

  @$internal
  @override
  SettingsController create() => SettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AleraSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AleraSettings>(value),
    );
  }
}

String _$settingsControllerHash() =>
    r'3dae19d0a5a2ed1840e3e2b139e91cc4f56ea002';

abstract class _$SettingsController extends $Notifier<AleraSettings> {
  AleraSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AleraSettings, AleraSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AleraSettings, AleraSettings>,
              AleraSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
