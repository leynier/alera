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

@ProviderFor(commandEnvironmentResolver)
final commandEnvironmentResolverProvider =
    CommandEnvironmentResolverProvider._();

final class CommandEnvironmentResolverProvider
    extends
        $FunctionalProvider<
          CommandEnvironmentResolver,
          CommandEnvironmentResolver,
          CommandEnvironmentResolver
        >
    with $Provider<CommandEnvironmentResolver> {
  CommandEnvironmentResolverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commandEnvironmentResolverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commandEnvironmentResolverHash();

  @$internal
  @override
  $ProviderElement<CommandEnvironmentResolver> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CommandEnvironmentResolver create(Ref ref) {
    return commandEnvironmentResolver(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommandEnvironmentResolver value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommandEnvironmentResolver>(value),
    );
  }
}

String _$commandEnvironmentResolverHash() =>
    r'9918842e9c6d996f810f2760a6dc5dec158349cd';
