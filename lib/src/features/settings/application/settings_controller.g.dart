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
    r'2668ef9e2e3b3702259581beb024d47148368896';

abstract class _$SettingsController extends $Notifier<AleraSettings> {
  AleraSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AleraSettings, AleraSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AleraSettings, AleraSettings>,
              AleraSettings,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
