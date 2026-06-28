// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_host_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runtimeHostClient)
final runtimeHostClientProvider = RuntimeHostClientProvider._();

final class RuntimeHostClientProvider
    extends
        $FunctionalProvider<
          SocketTerminalHostClient,
          SocketTerminalHostClient,
          SocketTerminalHostClient
        >
    with $Provider<SocketTerminalHostClient> {
  RuntimeHostClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeHostClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeHostClientHash();

  @$internal
  @override
  $ProviderElement<SocketTerminalHostClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SocketTerminalHostClient create(Ref ref) {
    return runtimeHostClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SocketTerminalHostClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SocketTerminalHostClient>(value),
    );
  }
}

String _$runtimeHostClientHash() => r'60780d6cfec535f1c297fb6b66e31d23fc23837a';
