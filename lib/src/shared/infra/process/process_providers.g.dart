// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'process_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(processRunner)
final processRunnerProvider = ProcessRunnerProvider._();

final class ProcessRunnerProvider
    extends $FunctionalProvider<ProcessRunner, ProcessRunner, ProcessRunner>
    with $Provider<ProcessRunner> {
  ProcessRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'processRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$processRunnerHash();

  @$internal
  @override
  $ProviderElement<ProcessRunner> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProcessRunner create(Ref ref) {
    return processRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProcessRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProcessRunner>(value),
    );
  }
}

String _$processRunnerHash() => r'31828dd7bbb881a503b5721540d6ad6d9ed58b24';
