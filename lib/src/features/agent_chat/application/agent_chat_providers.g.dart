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

/// Provider instances a workspace's runtime can start chats with.

@ProviderFor(agentChatProviderCatalog)
final agentChatProviderCatalogProvider = AgentChatProviderCatalogFamily._();

/// Provider instances a workspace's runtime can start chats with.

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
  /// Provider instances a workspace's runtime can start chats with.
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
    r'd4c730657f0b512f3be30d03dd3ea2d29d9cfc90';

/// Provider instances a workspace's runtime can start chats with.

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

  /// Provider instances a workspace's runtime can start chats with.

  AgentChatProviderCatalogProvider call(String workspaceId) =>
      AgentChatProviderCatalogProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'agentChatProviderCatalogProvider';
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

/// The provider instance the last new chat started with, offered first the
/// next time in this session.

@ProviderFor(AgentChatLaunchPreference)
final agentChatLaunchPreferenceProvider = AgentChatLaunchPreferenceProvider._();

/// The provider instance the last new chat started with, offered first the
/// next time in this session.
final class AgentChatLaunchPreferenceProvider
    extends $NotifierProvider<AgentChatLaunchPreference, String?> {
  /// The provider instance the last new chat started with, offered first the
  /// next time in this session.
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
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$agentChatLaunchPreferenceHash() =>
    r'd247ba02ab01e44cf0aaccac008d633ef9969cd7';

/// The provider instance the last new chat started with, offered first the
/// next time in this session.

abstract class _$AgentChatLaunchPreference extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
