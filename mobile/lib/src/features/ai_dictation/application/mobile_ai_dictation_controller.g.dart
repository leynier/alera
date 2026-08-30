// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_ai_dictation_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileAiDictationOnDeviceAvailable)
final mobileAiDictationOnDeviceAvailableProvider =
    MobileAiDictationOnDeviceAvailableFamily._();

final class MobileAiDictationOnDeviceAvailableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  MobileAiDictationOnDeviceAvailableProvider._({
    required MobileAiDictationOnDeviceAvailableFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'mobileAiDictationOnDeviceAvailableProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$mobileAiDictationOnDeviceAvailableHash();

  @override
  String toString() {
    return r'mobileAiDictationOnDeviceAvailableProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String?;
    return mobileAiDictationOnDeviceAvailable(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAiDictationOnDeviceAvailableProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAiDictationOnDeviceAvailableHash() =>
    r'1fa250a2a40e26ef34e2e71882b9930fd0d7ed42';

final class MobileAiDictationOnDeviceAvailableFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String?> {
  MobileAiDictationOnDeviceAvailableFamily._()
    : super(
        retry: null,
        name: r'mobileAiDictationOnDeviceAvailableProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAiDictationOnDeviceAvailableProvider call(String? localeId) =>
      MobileAiDictationOnDeviceAvailableProvider._(
        argument: localeId,
        from: this,
      );

  @override
  String toString() => r'mobileAiDictationOnDeviceAvailableProvider';
}

@ProviderFor(MobileAiDictationController)
final mobileAiDictationControllerProvider =
    MobileAiDictationControllerFamily._();

final class MobileAiDictationControllerProvider
    extends
        $NotifierProvider<MobileAiDictationController, MobileAiDictationState> {
  MobileAiDictationControllerProvider._({
    required MobileAiDictationControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAiDictationControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAiDictationControllerHash();

  @override
  String toString() {
    return r'mobileAiDictationControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileAiDictationController create() => MobileAiDictationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileAiDictationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileAiDictationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAiDictationControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAiDictationControllerHash() =>
    r'adebeb31fbd426c5545ff53571e0d68933204986';

final class MobileAiDictationControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAiDictationController,
          MobileAiDictationState,
          MobileAiDictationState,
          MobileAiDictationState,
          (String, String)
        > {
  MobileAiDictationControllerFamily._()
    : super(
        retry: null,
        name: r'mobileAiDictationControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAiDictationControllerProvider call(String hostId, String targetKey) =>
      MobileAiDictationControllerProvider._(
        argument: (hostId, targetKey),
        from: this,
      );

  @override
  String toString() => r'mobileAiDictationControllerProvider';
}

abstract class _$MobileAiDictationController
    extends $Notifier<MobileAiDictationState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get targetKey => _$args.$2;

  MobileAiDictationState build(String hostId, String targetKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<MobileAiDictationState, MobileAiDictationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileAiDictationState, MobileAiDictationState>,
              MobileAiDictationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
