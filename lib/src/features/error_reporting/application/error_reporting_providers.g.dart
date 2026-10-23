// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_reporting_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiErrorClarifier)
final aiErrorClarifierProvider = AiErrorClarifierProvider._();

final class AiErrorClarifierProvider
    extends
        $FunctionalProvider<
          AiErrorClarifier,
          AiErrorClarifier,
          AiErrorClarifier
        >
    with $Provider<AiErrorClarifier> {
  AiErrorClarifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiErrorClarifierProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiErrorClarifierHash();

  @$internal
  @override
  $ProviderElement<AiErrorClarifier> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AiErrorClarifier create(Ref ref) {
    return aiErrorClarifier(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiErrorClarifier value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiErrorClarifier>(value),
    );
  }
}

String _$aiErrorClarifierHash() => r'cc9b32b725ce26725f4ed0482f6287a55fad89a1';
