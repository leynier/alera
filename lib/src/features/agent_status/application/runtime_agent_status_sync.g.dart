// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_agent_status_sync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runtimeAgentStatusSync)
final runtimeAgentStatusSyncProvider = RuntimeAgentStatusSyncProvider._();

final class RuntimeAgentStatusSyncProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  RuntimeAgentStatusSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeAgentStatusSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeAgentStatusSyncHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return runtimeAgentStatusSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$runtimeAgentStatusSyncHash() =>
    r'aeb5cc640eb9515ecc699ec0bf6d98e743e8669d';
