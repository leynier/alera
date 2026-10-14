// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_provider_settings_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The paired runtime's settings service for chat agents.

@ProviderFor(agentProviderSettingsRepository)
final agentProviderSettingsRepositoryProvider =
    AgentProviderSettingsRepositoryFamily._();

/// The paired runtime's settings service for chat agents.

final class AgentProviderSettingsRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatSettingsRepository>,
          AgentChatSettingsRepository,
          FutureOr<AgentChatSettingsRepository>
        >
    with
        $FutureModifier<AgentChatSettingsRepository>,
        $FutureProvider<AgentChatSettingsRepository> {
  /// The paired runtime's settings service for chat agents.
  AgentProviderSettingsRepositoryProvider._({
    required AgentProviderSettingsRepositoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentProviderSettingsRepositoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProviderSettingsRepositoryHash();

  @override
  String toString() {
    return r'agentProviderSettingsRepositoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatSettingsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatSettingsRepository> create(Ref ref) {
    final argument = this.argument as String;
    return agentProviderSettingsRepository(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentProviderSettingsRepositoryProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProviderSettingsRepositoryHash() =>
    r'a663b0157727a05d3a9f0f53628f62a0c708e2a3';

/// The paired runtime's settings service for chat agents.

final class AgentProviderSettingsRepositoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatSettingsRepository>,
          String
        > {
  AgentProviderSettingsRepositoryFamily._()
    : super(
        retry: null,
        name: r'agentProviderSettingsRepositoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The paired runtime's settings service for chat agents.

  AgentProviderSettingsRepositoryProvider call(String hostId) =>
      AgentProviderSettingsRepositoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentProviderSettingsRepositoryProvider';
}

/// Every agent instance on one host with the status the host last verified.
/// [remoteHostId] is a Remote Host behind the paired runtime; null is the
/// paired runtime itself. The answer comes from the host's status cache, so
/// opening this does not probe providers; Refresh does.

@ProviderFor(agentProviderCatalog)
final agentProviderCatalogProvider = AgentProviderCatalogFamily._();

/// Every agent instance on one host with the status the host last verified.
/// [remoteHostId] is a Remote Host behind the paired runtime; null is the
/// paired runtime itself. The answer comes from the host's status cache, so
/// opening this does not probe providers; Refresh does.

final class AgentProviderCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatProviderInstance>>,
          List<AgentChatProviderInstance>,
          FutureOr<List<AgentChatProviderInstance>>
        >
    with
        $FutureModifier<List<AgentChatProviderInstance>>,
        $FutureProvider<List<AgentChatProviderInstance>> {
  /// Every agent instance on one host with the status the host last verified.
  /// [remoteHostId] is a Remote Host behind the paired runtime; null is the
  /// paired runtime itself. The answer comes from the host's status cache, so
  /// opening this does not probe providers; Refresh does.
  AgentProviderCatalogProvider._({
    required AgentProviderCatalogFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'agentProviderCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProviderCatalogHash();

  @override
  String toString() {
    return r'agentProviderCatalogProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatProviderInstance>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatProviderInstance>> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return agentProviderCatalog(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentProviderCatalogProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProviderCatalogHash() =>
    r'cf47f37d9a915be1b597c543b795f4fb2a9db198';

/// Every agent instance on one host with the status the host last verified.
/// [remoteHostId] is a Remote Host behind the paired runtime; null is the
/// paired runtime itself. The answer comes from the host's status cache, so
/// opening this does not probe providers; Refresh does.

final class AgentProviderCatalogFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatProviderInstance>>,
          (String, String?)
        > {
  AgentProviderCatalogFamily._()
    : super(
        retry: null,
        name: r'agentProviderCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every agent instance on one host with the status the host last verified.
  /// [remoteHostId] is a Remote Host behind the paired runtime; null is the
  /// paired runtime itself. The answer comes from the host's status cache, so
  /// opening this does not probe providers; Refresh does.

  AgentProviderCatalogProvider call(String hostId, String? remoteHostId) =>
      AgentProviderCatalogProvider._(
        argument: (hostId, remoteHostId),
        from: this,
      );

  @override
  String toString() => r'agentProviderCatalogProvider';
}

/// The host's stored instance settings, or null on a runtime that keeps
/// none, where the screen stays read-only.

@ProviderFor(agentProviderInstances)
final agentProviderInstancesProvider = AgentProviderInstancesFamily._();

/// The host's stored instance settings, or null on a runtime that keeps
/// none, where the screen stays read-only.

final class AgentProviderInstancesProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatProviderSettingsSnapshot?>,
          AgentChatProviderSettingsSnapshot?,
          FutureOr<AgentChatProviderSettingsSnapshot?>
        >
    with
        $FutureModifier<AgentChatProviderSettingsSnapshot?>,
        $FutureProvider<AgentChatProviderSettingsSnapshot?> {
  /// The host's stored instance settings, or null on a runtime that keeps
  /// none, where the screen stays read-only.
  AgentProviderInstancesProvider._({
    required AgentProviderInstancesFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'agentProviderInstancesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProviderInstancesHash();

  @override
  String toString() {
    return r'agentProviderInstancesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatProviderSettingsSnapshot?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatProviderSettingsSnapshot?> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return agentProviderInstances(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentProviderInstancesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProviderInstancesHash() =>
    r'6cd6e39c9082b1273677c6c01efafdcca6ba27d5';

/// The host's stored instance settings, or null on a runtime that keeps
/// none, where the screen stays read-only.

final class AgentProviderInstancesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatProviderSettingsSnapshot?>,
          (String, String?)
        > {
  AgentProviderInstancesFamily._()
    : super(
        retry: null,
        name: r'agentProviderInstancesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The host's stored instance settings, or null on a runtime that keeps
  /// none, where the screen stays read-only.

  AgentProviderInstancesProvider call(String hostId, String? remoteHostId) =>
      AgentProviderInstancesProvider._(
        argument: (hostId, remoteHostId),
        from: this,
      );

  @override
  String toString() => r'agentProviderInstancesProvider';
}
