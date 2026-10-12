// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_host_usage_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(remoteHostUsage)
final remoteHostUsageProvider = RemoteHostUsageProvider._();

final class RemoteHostUsageProvider
    extends
        $FunctionalProvider<
          Map<String, RemoteHostUsage>,
          Map<String, RemoteHostUsage>,
          Map<String, RemoteHostUsage>
        >
    with $Provider<Map<String, RemoteHostUsage>> {
  RemoteHostUsageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteHostUsageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteHostUsageHash();

  @$internal
  @override
  $ProviderElement<Map<String, RemoteHostUsage>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, RemoteHostUsage> create(Ref ref) {
    return remoteHostUsage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, RemoteHostUsage> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, RemoteHostUsage>>(value),
    );
  }
}

String _$remoteHostUsageHash() => r'a839ab468a6244473c3ff04c9c89f595d6371005';
