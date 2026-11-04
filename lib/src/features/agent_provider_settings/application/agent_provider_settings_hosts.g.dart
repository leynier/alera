// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_provider_settings_hosts.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// This Device first, then every Remote Host with an installed runtime, in
/// the order Remote Hosts lists them. A host that is offline stays listed
/// because the hub connects on demand; its state is shown beside its name.

@ProviderFor(agentProviderHostOptions)
final agentProviderHostOptionsProvider = AgentProviderHostOptionsProvider._();

/// This Device first, then every Remote Host with an installed runtime, in
/// the order Remote Hosts lists them. A host that is offline stays listed
/// because the hub connects on demand; its state is shown beside its name.

final class AgentProviderHostOptionsProvider
    extends
        $FunctionalProvider<
          List<AgentProviderHostOption>,
          List<AgentProviderHostOption>,
          List<AgentProviderHostOption>
        >
    with $Provider<List<AgentProviderHostOption>> {
  /// This Device first, then every Remote Host with an installed runtime, in
  /// the order Remote Hosts lists them. A host that is offline stays listed
  /// because the hub connects on demand; its state is shown beside its name.
  AgentProviderHostOptionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProviderHostOptionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProviderHostOptionsHash();

  @$internal
  @override
  $ProviderElement<List<AgentProviderHostOption>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<AgentProviderHostOption> create(Ref ref) {
    return agentProviderHostOptions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AgentProviderHostOption> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AgentProviderHostOption>>(
        value,
      ),
    );
  }
}

String _$agentProviderHostOptionsHash() =>
    r'2152cedd0e72b27eb238b21b2df8bc30b952ddba';

/// The active workspace's host id, normalized so This Device is null.

@ProviderFor(agentProviderActiveWorkspaceHost)
final agentProviderActiveWorkspaceHostProvider =
    AgentProviderActiveWorkspaceHostProvider._();

/// The active workspace's host id, normalized so This Device is null.

final class AgentProviderActiveWorkspaceHostProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The active workspace's host id, normalized so This Device is null.
  AgentProviderActiveWorkspaceHostProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProviderActiveWorkspaceHostProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProviderActiveWorkspaceHostHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return agentProviderActiveWorkspaceHost(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$agentProviderActiveWorkspaceHostHash() =>
    r'6d234c761329165253d8cfbcf72eaf5b0de105d5';

/// Projects a default can be set for, by id and name, in sidebar order.

@ProviderFor(agentProviderProjects)
final agentProviderProjectsProvider = AgentProviderProjectsProvider._();

/// Projects a default can be set for, by id and name, in sidebar order.

final class AgentProviderProjectsProvider
    extends
        $FunctionalProvider<
          List<({String id, String name})>,
          List<({String id, String name})>,
          List<({String id, String name})>
        >
    with $Provider<List<({String id, String name})>> {
  /// Projects a default can be set for, by id and name, in sidebar order.
  AgentProviderProjectsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProviderProjectsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProviderProjectsHash();

  @$internal
  @override
  $ProviderElement<List<({String id, String name})>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<({String id, String name})> create(Ref ref) {
    return agentProviderProjects(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<({String id, String name})> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<({String id, String name})>>(
        value,
      ),
    );
  }
}

String _$agentProviderProjectsHash() =>
    r'3c5e03ecbab7b1ebcdd65c07295803f716682565';
