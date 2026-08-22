// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_ai_dictation_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MobileAiDictationSettingsController)
final mobileAiDictationSettingsControllerProvider =
    MobileAiDictationSettingsControllerProvider._();

final class MobileAiDictationSettingsControllerProvider
    extends
        $AsyncNotifierProvider<
          MobileAiDictationSettingsController,
          MobileAiDictationSettings
        > {
  MobileAiDictationSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileAiDictationSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$mobileAiDictationSettingsControllerHash();

  @$internal
  @override
  MobileAiDictationSettingsController create() =>
      MobileAiDictationSettingsController();
}

String _$mobileAiDictationSettingsControllerHash() =>
    r'2d3c01ef1cbc0ef3f1d1900ebd17fcdf1a123ca7';

abstract class _$MobileAiDictationSettingsController
    extends $AsyncNotifier<MobileAiDictationSettings> {
  FutureOr<MobileAiDictationSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<MobileAiDictationSettings>,
              MobileAiDictationSettings
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<MobileAiDictationSettings>,
                MobileAiDictationSettings
              >,
              AsyncValue<MobileAiDictationSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
