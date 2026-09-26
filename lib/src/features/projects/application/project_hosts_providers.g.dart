// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_hosts_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(projectHostsClient)
final projectHostsClientProvider = ProjectHostsClientProvider._();

final class ProjectHostsClientProvider
    extends
        $FunctionalProvider<
          RuntimeProjectHostsClient,
          RuntimeProjectHostsClient,
          RuntimeProjectHostsClient
        >
    with $Provider<RuntimeProjectHostsClient> {
  ProjectHostsClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectHostsClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectHostsClientHash();

  @$internal
  @override
  $ProviderElement<RuntimeProjectHostsClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeProjectHostsClient create(Ref ref) {
    return projectHostsClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeProjectHostsClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeProjectHostsClient>(value),
    );
  }
}

String _$projectHostsClientHash() =>
    r'c5b2bf532af5b909aeec74642e0d282b31fe804c';

/// Whether the connected runtime can put one project on several hosts. An
/// unreachable runtime reads as unsupported so no control is offered that the
/// host would reject.

@ProviderFor(projectHostsSupported)
final projectHostsSupportedProvider = ProjectHostsSupportedProvider._();

/// Whether the connected runtime can put one project on several hosts. An
/// unreachable runtime reads as unsupported so no control is offered that the
/// host would reject.

final class ProjectHostsSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the connected runtime can put one project on several hosts. An
  /// unreachable runtime reads as unsupported so no control is offered that the
  /// host would reject.
  ProjectHostsSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectHostsSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectHostsSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return projectHostsSupported(ref);
  }
}

String _$projectHostsSupportedHash() =>
    r'46a06810ec1314f8fab221e364d36c03ac8b76a2';
