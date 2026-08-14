// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_ai_dictation_recognizer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiDictationOnDeviceAvailable)
final aiDictationOnDeviceAvailableProvider =
    AiDictationOnDeviceAvailableFamily._();

final class AiDictationOnDeviceAvailableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  AiDictationOnDeviceAvailableProvider._({
    required AiDictationOnDeviceAvailableFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'aiDictationOnDeviceAvailableProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiDictationOnDeviceAvailableHash();

  @override
  String toString() {
    return r'aiDictationOnDeviceAvailableProvider'
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
    return aiDictationOnDeviceAvailable(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiDictationOnDeviceAvailableProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiDictationOnDeviceAvailableHash() =>
    r'665c8fdbfe9f73ddd3bb1d8b182937ea25ac1ad2';

final class AiDictationOnDeviceAvailableFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String?> {
  AiDictationOnDeviceAvailableFamily._()
    : super(
        retry: null,
        name: r'aiDictationOnDeviceAvailableProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AiDictationOnDeviceAvailableProvider call(String? localeId) =>
      AiDictationOnDeviceAvailableProvider._(argument: localeId, from: this);

  @override
  String toString() => r'aiDictationOnDeviceAvailableProvider';
}
