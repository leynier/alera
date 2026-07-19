// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(hostRepository)
final hostRepositoryProvider = HostRepositoryProvider._();

final class HostRepositoryProvider
    extends $FunctionalProvider<HostRepository, HostRepository, HostRepository>
    with $Provider<HostRepository> {
  HostRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostRepositoryHash();

  @$internal
  @override
  $ProviderElement<HostRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HostRepository create(Ref ref) {
    return hostRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HostRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HostRepository>(value),
    );
  }
}

String _$hostRepositoryHash() => r'198cd7231d2651803315fbb7a80bb7cf15a840f4';
