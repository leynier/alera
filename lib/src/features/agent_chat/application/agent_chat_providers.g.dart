// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatRepository)
final agentChatRepositoryProvider = AgentChatRepositoryProvider._();

final class AgentChatRepositoryProvider
    extends
        $FunctionalProvider<
          AgentChatRepository,
          AgentChatRepository,
          AgentChatRepository
        >
    with $Provider<AgentChatRepository> {
  AgentChatRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatRepositoryHash();

  @$internal
  @override
  $ProviderElement<AgentChatRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatRepository create(Ref ref) {
    return agentChatRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatRepository>(value),
    );
  }
}

String _$agentChatRepositoryHash() =>
    r'e8ff7657b77ec6c8a34734b1317152dae0b9e374';

/// Preferences and provider settings of the connected runtime. Repositories
/// without them (older runtimes, test fakes) answer as unsupported.

@ProviderFor(agentChatSettingsRepository)
final agentChatSettingsRepositoryProvider =
    AgentChatSettingsRepositoryProvider._();

/// Preferences and provider settings of the connected runtime. Repositories
/// without them (older runtimes, test fakes) answer as unsupported.

final class AgentChatSettingsRepositoryProvider
    extends
        $FunctionalProvider<
          AgentChatSettingsRepository,
          AgentChatSettingsRepository,
          AgentChatSettingsRepository
        >
    with $Provider<AgentChatSettingsRepository> {
  /// Preferences and provider settings of the connected runtime. Repositories
  /// without them (older runtimes, test fakes) answer as unsupported.
  AgentChatSettingsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatSettingsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatSettingsRepositoryHash();

  @$internal
  @override
  $ProviderElement<AgentChatSettingsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatSettingsRepository create(Ref ref) {
    return agentChatSettingsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatSettingsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatSettingsRepository>(value),
    );
  }
}

String _$agentChatSettingsRepositoryHash() =>
    r'5f7fdab5fc8da9821b286e5b8128e9669d61becc';

/// Chat controls that only newer runtimes offer, such as editing a queued
/// message or steering it into the running turn.

@ProviderFor(agentChatLifecycleRepository)
final agentChatLifecycleRepositoryProvider =
    AgentChatLifecycleRepositoryProvider._();

/// Chat controls that only newer runtimes offer, such as editing a queued
/// message or steering it into the running turn.

final class AgentChatLifecycleRepositoryProvider
    extends
        $FunctionalProvider<
          AgentChatLifecycleRepository,
          AgentChatLifecycleRepository,
          AgentChatLifecycleRepository
        >
    with $Provider<AgentChatLifecycleRepository> {
  /// Chat controls that only newer runtimes offer, such as editing a queued
  /// message or steering it into the running turn.
  AgentChatLifecycleRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatLifecycleRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatLifecycleRepositoryHash();

  @$internal
  @override
  $ProviderElement<AgentChatLifecycleRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatLifecycleRepository create(Ref ref) {
    return agentChatLifecycleRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatLifecycleRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatLifecycleRepository>(value),
    );
  }
}

String _$agentChatLifecycleRepositoryHash() =>
    r'ca0f7602d9a7dd6265feba2cc6e95d7ee1e822e7';

/// Whether the connected runtime runs agent chats. An unreachable runtime
/// reads as unsupported so no entry point is offered that would fail.

@ProviderFor(agentChatSupported)
final agentChatSupportedProvider = AgentChatSupportedProvider._();

/// Whether the connected runtime runs agent chats. An unreachable runtime
/// reads as unsupported so no entry point is offered that would fail.

final class AgentChatSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the connected runtime runs agent chats. An unreachable runtime
  /// reads as unsupported so no entry point is offered that would fail.
  AgentChatSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return agentChatSupported(ref);
  }
}

String _$agentChatSupportedHash() =>
    r'193502529c1de6efa172bd64146bc99f5334d4ff';

/// Whether the runtime advertises one of the additive `AgentChatWire`
/// capabilities. A failed check reads as unsupported.

@ProviderFor(agentChatCapability)
final agentChatCapabilityProvider = AgentChatCapabilityFamily._();

/// Whether the runtime advertises one of the additive `AgentChatWire`
/// capabilities. A failed check reads as unsupported.

final class AgentChatCapabilityProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the runtime advertises one of the additive `AgentChatWire`
  /// capabilities. A failed check reads as unsupported.
  AgentChatCapabilityProvider._({
    required AgentChatCapabilityFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatCapabilityProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatCapabilityHash();

  @override
  String toString() {
    return r'agentChatCapabilityProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return agentChatCapability(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatCapabilityProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatCapabilityHash() =>
    r'81fe5effd12c6d26e0b8109a0030bf58636f14e0';

/// Whether the runtime advertises one of the additive `AgentChatWire`
/// capabilities. A failed check reads as unsupported.

final class AgentChatCapabilityFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  AgentChatCapabilityFamily._()
    : super(
        retry: null,
        name: r'agentChatCapabilityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the runtime advertises one of the additive `AgentChatWire`
  /// capabilities. A failed check reads as unsupported.

  AgentChatCapabilityProvider call(String capability) =>
      AgentChatCapabilityProvider._(argument: capability, from: this);

  @override
  String toString() => r'agentChatCapabilityProvider';
}

/// Provider instances a workspace's runtime can start chats with. A provider
/// settings change on the runtime reads the catalog again.

@ProviderFor(agentChatProviderCatalog)
final agentChatProviderCatalogProvider = AgentChatProviderCatalogFamily._();

/// Provider instances a workspace's runtime can start chats with. A provider
/// settings change on the runtime reads the catalog again.

final class AgentChatProviderCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatProviderInstance>>,
          List<AgentChatProviderInstance>,
          FutureOr<List<AgentChatProviderInstance>>
        >
    with
        $FutureModifier<List<AgentChatProviderInstance>>,
        $FutureProvider<List<AgentChatProviderInstance>> {
  /// Provider instances a workspace's runtime can start chats with. A provider
  /// settings change on the runtime reads the catalog again.
  AgentChatProviderCatalogProvider._({
    required AgentChatProviderCatalogFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatProviderCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatProviderCatalogHash();

  @override
  String toString() {
    return r'agentChatProviderCatalogProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatProviderInstance>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatProviderInstance>> create(Ref ref) {
    final argument = this.argument as String;
    return agentChatProviderCatalog(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatProviderCatalogProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatProviderCatalogHash() =>
    r'2f87cfe6e47d72d341573f201956eedc2caae3ff';

/// Provider instances a workspace's runtime can start chats with. A provider
/// settings change on the runtime reads the catalog again.

final class AgentChatProviderCatalogFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatProviderInstance>>,
          String
        > {
  AgentChatProviderCatalogFamily._()
    : super(
        retry: null,
        name: r'agentChatProviderCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider instances a workspace's runtime can start chats with. A provider
  /// settings change on the runtime reads the catalog again.

  AgentChatProviderCatalogProvider call(String workspaceId) =>
      AgentChatProviderCatalogProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'agentChatProviderCatalogProvider';
}

/// The runtime's chat preferences for [hostId] (see [agentChatHostKey]).
/// Empty preferences when the runtime does not keep them; Settings checks
/// [AgentChatSettingsRepository.preferencesSupported] on its own.

@ProviderFor(agentChatPreferences)
final agentChatPreferencesProvider = AgentChatPreferencesFamily._();

/// The runtime's chat preferences for [hostId] (see [agentChatHostKey]).
/// Empty preferences when the runtime does not keep them; Settings checks
/// [AgentChatSettingsRepository.preferencesSupported] on its own.

final class AgentChatPreferencesProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatPreferences>,
          AgentChatPreferences,
          FutureOr<AgentChatPreferences>
        >
    with
        $FutureModifier<AgentChatPreferences>,
        $FutureProvider<AgentChatPreferences> {
  /// The runtime's chat preferences for [hostId] (see [agentChatHostKey]).
  /// Empty preferences when the runtime does not keep them; Settings checks
  /// [AgentChatSettingsRepository.preferencesSupported] on its own.
  AgentChatPreferencesProvider._({
    required AgentChatPreferencesFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentChatPreferencesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatPreferencesHash();

  @override
  String toString() {
    return r'agentChatPreferencesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatPreferences> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatPreferences> create(Ref ref) {
    final argument = this.argument as String?;
    return agentChatPreferences(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatPreferencesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatPreferencesHash() =>
    r'6674ccdfa6ac18e0db561fb8e6960227be797087';

/// The runtime's chat preferences for [hostId] (see [agentChatHostKey]).
/// Empty preferences when the runtime does not keep them; Settings checks
/// [AgentChatSettingsRepository.preferencesSupported] on its own.

final class AgentChatPreferencesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentChatPreferences>, String?> {
  AgentChatPreferencesFamily._()
    : super(
        retry: null,
        name: r'agentChatPreferencesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The runtime's chat preferences for [hostId] (see [agentChatHostKey]).
  /// Empty preferences when the runtime does not keep them; Settings checks
  /// [AgentChatSettingsRepository.preferencesSupported] on its own.

  AgentChatPreferencesProvider call(String? hostId) =>
      AgentChatPreferencesProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentChatPreferencesProvider';
}

/// Allocates request and client message ids; tests pin it.

@ProviderFor(agentChatIdGenerator)
final agentChatIdGeneratorProvider = AgentChatIdGeneratorProvider._();

/// Allocates request and client message ids; tests pin it.

final class AgentChatIdGeneratorProvider
    extends
        $FunctionalProvider<
          String Function(),
          String Function(),
          String Function()
        >
    with $Provider<String Function()> {
  /// Allocates request and client message ids; tests pin it.
  AgentChatIdGeneratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatIdGeneratorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatIdGeneratorHash();

  @$internal
  @override
  $ProviderElement<String Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  String Function() create(Ref ref) {
    return agentChatIdGenerator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String Function()>(value),
    );
  }
}

String _$agentChatIdGeneratorHash() =>
    r'63e93d97ef6b5f7855e6ae630154cc1bc2044d61';

/// The clock optimistic messages and live turn timers read; tests pin it.

@ProviderFor(agentChatClock)
final agentChatClockProvider = AgentChatClockProvider._();

/// The clock optimistic messages and live turn timers read; tests pin it.

final class AgentChatClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The clock optimistic messages and live turn timers read; tests pin it.
  AgentChatClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return agentChatClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$agentChatClockHash() => r'4e8cbcbdaa2b6c9c73224b3e46ec37c2e4d7b328';

/// Unsent composer text and attachments per chat. Kept for the session so a
/// tab switch or a reconnect never loses a draft.

@ProviderFor(agentChatComposerDrafts)
final agentChatComposerDraftsProvider = AgentChatComposerDraftsProvider._();

/// Unsent composer text and attachments per chat. Kept for the session so a
/// tab switch or a reconnect never loses a draft.

final class AgentChatComposerDraftsProvider
    extends
        $FunctionalProvider<
          AgentChatComposerDrafts,
          AgentChatComposerDrafts,
          AgentChatComposerDrafts
        >
    with $Provider<AgentChatComposerDrafts> {
  /// Unsent composer text and attachments per chat. Kept for the session so a
  /// tab switch or a reconnect never loses a draft.
  AgentChatComposerDraftsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatComposerDraftsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatComposerDraftsHash();

  @$internal
  @override
  $ProviderElement<AgentChatComposerDrafts> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatComposerDrafts create(Ref ref) {
    return agentChatComposerDrafts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatComposerDrafts value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatComposerDrafts>(value),
    );
  }
}

String _$agentChatComposerDraftsHash() =>
    r'13578dd1cae5f3f683b8ade73e1449a1761ffb9a';

/// The selection of the last chat that sent its first message in this
/// session. Runtimes with chat preferences remember it themselves; this only
/// stands in for runtimes that do not.

@ProviderFor(AgentChatLaunchPreference)
final agentChatLaunchPreferenceProvider = AgentChatLaunchPreferenceProvider._();

/// The selection of the last chat that sent its first message in this
/// session. Runtimes with chat preferences remember it themselves; this only
/// stands in for runtimes that do not.
final class AgentChatLaunchPreferenceProvider
    extends $NotifierProvider<AgentChatLaunchPreference, AgentChatSelection?> {
  /// The selection of the last chat that sent its first message in this
  /// session. Runtimes with chat preferences remember it themselves; this only
  /// stands in for runtimes that do not.
  AgentChatLaunchPreferenceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatLaunchPreferenceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatLaunchPreferenceHash();

  @$internal
  @override
  AgentChatLaunchPreference create() => AgentChatLaunchPreference();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatSelection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatSelection?>(value),
    );
  }
}

String _$agentChatLaunchPreferenceHash() =>
    r'2d346b33da31e4cb1ddc9b57acd285985b4d522a';

/// The selection of the last chat that sent its first message in this
/// session. Runtimes with chat preferences remember it themselves; this only
/// stands in for runtimes that do not.

abstract class _$AgentChatLaunchPreference
    extends $Notifier<AgentChatSelection?> {
  AgentChatSelection? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentChatSelection?, AgentChatSelection?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentChatSelection?, AgentChatSelection?>,
              AgentChatSelection?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
