// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The paired runtime as agent chats see it: the same connection the
/// workspace screens use, so it rebuilds with every reconnect, which is what
/// makes each open chat reload its snapshot.

@ProviderFor(mobileAgentChatClient)
final mobileAgentChatClientProvider = MobileAgentChatClientFamily._();

/// The paired runtime as agent chats see it: the same connection the
/// workspace screens use, so it rebuilds with every reconnect, which is what
/// makes each open chat reload its snapshot.

final class MobileAgentChatClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAgentChatClient>,
          MobileAgentChatClient,
          FutureOr<MobileAgentChatClient>
        >
    with
        $FutureModifier<MobileAgentChatClient>,
        $FutureProvider<MobileAgentChatClient> {
  /// The paired runtime as agent chats see it: the same connection the
  /// workspace screens use, so it rebuilds with every reconnect, which is what
  /// makes each open chat reload its snapshot.
  MobileAgentChatClientProvider._({
    required MobileAgentChatClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAgentChatClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAgentChatClientHash();

  @override
  String toString() {
    return r'mobileAgentChatClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileAgentChatClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileAgentChatClient> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAgentChatClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAgentChatClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAgentChatClientHash() =>
    r'4615d51e86c3b4c8f5a1b62b9019802849201137';

/// The paired runtime as agent chats see it: the same connection the
/// workspace screens use, so it rebuilds with every reconnect, which is what
/// makes each open chat reload its snapshot.

final class MobileAgentChatClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileAgentChatClient>, String> {
  MobileAgentChatClientFamily._()
    : super(
        retry: null,
        name: r'mobileAgentChatClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The paired runtime as agent chats see it: the same connection the
  /// workspace screens use, so it rebuilds with every reconnect, which is what
  /// makes each open chat reload its snapshot.

  MobileAgentChatClientProvider call(String hostId) =>
      MobileAgentChatClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAgentChatClientProvider';
}

@ProviderFor(agentChatRepository)
final agentChatRepositoryProvider = AgentChatRepositoryFamily._();

final class AgentChatRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatRepository>,
          AgentChatRepository,
          FutureOr<AgentChatRepository>
        >
    with
        $FutureModifier<AgentChatRepository>,
        $FutureProvider<AgentChatRepository> {
  AgentChatRepositoryProvider._({
    required AgentChatRepositoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatRepositoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatRepositoryHash();

  @override
  String toString() {
    return r'agentChatRepositoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatRepository> create(Ref ref) {
    final argument = this.argument as String;
    return agentChatRepository(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatRepositoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatRepositoryHash() =>
    r'cfb71ea0627d5a60324fcf3b6253d9ca914d6dca';

final class AgentChatRepositoryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentChatRepository>, String> {
  AgentChatRepositoryFamily._()
    : super(
        retry: null,
        name: r'agentChatRepositoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentChatRepositoryProvider call(String hostId) =>
      AgentChatRepositoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentChatRepositoryProvider';
}

/// Whether the paired runtime serves agent chats; New Chat is offered only
/// when it does. An older runtime, or a client without the surface, is a
/// plain no rather than an error.

@ProviderFor(agentChatSupported)
final agentChatSupportedProvider = AgentChatSupportedFamily._();

/// Whether the paired runtime serves agent chats; New Chat is offered only
/// when it does. An older runtime, or a client without the surface, is a
/// plain no rather than an error.

final class AgentChatSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the paired runtime serves agent chats; New Chat is offered only
  /// when it does. An older runtime, or a client without the surface, is a
  /// plain no rather than an error.
  AgentChatSupportedProvider._({
    required AgentChatSupportedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatSupportedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatSupportedHash();

  @override
  String toString() {
    return r'agentChatSupportedProvider'
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
    return agentChatSupported(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatSupportedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatSupportedHash() =>
    r'd9761958344615373f668dab3e3130e949727790';

/// Whether the paired runtime serves agent chats; New Chat is offered only
/// when it does. An older runtime, or a client without the surface, is a
/// plain no rather than an error.

final class AgentChatSupportedFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  AgentChatSupportedFamily._()
    : super(
        retry: null,
        name: r'agentChatSupportedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the paired runtime serves agent chats; New Chat is offered only
  /// when it does. An older runtime, or a client without the surface, is a
  /// plain no rather than an error.

  AgentChatSupportedProvider call(String hostId) =>
      AgentChatSupportedProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentChatSupportedProvider';
}

/// Whether the paired runtime advertises [capability]. Every additive chat
/// control asks here first, so an older runtime keeps its older behavior.

@ProviderFor(agentChatCapability)
final agentChatCapabilityProvider = AgentChatCapabilityFamily._();

/// Whether the paired runtime advertises [capability]. Every additive chat
/// control asks here first, so an older runtime keeps its older behavior.

final class AgentChatCapabilityProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the paired runtime advertises [capability]. Every additive chat
  /// control asks here first, so an older runtime keeps its older behavior.
  AgentChatCapabilityProvider._({
    required AgentChatCapabilityFamily super.from,
    required (String, String) super.argument,
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
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as (String, String);
    return agentChatCapability(ref, argument.$1, argument.$2);
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
    r'a7c441bbdc2c76acdc670968b54915011e511a14';

/// Whether the paired runtime advertises [capability]. Every additive chat
/// control asks here first, so an older runtime keeps its older behavior.

final class AgentChatCapabilityFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, (String, String)> {
  AgentChatCapabilityFamily._()
    : super(
        retry: null,
        name: r'agentChatCapabilityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the paired runtime advertises [capability]. Every additive chat
  /// control asks here first, so an older runtime keeps its older behavior.

  AgentChatCapabilityProvider call(String hostId, String capability) =>
      AgentChatCapabilityProvider._(argument: (hostId, capability), from: this);

  @override
  String toString() => r'agentChatCapabilityProvider';
}

/// Chats of [workspaceId] that were closed; their history stays on the host
/// and Reopen brings one back in a new tab.

@ProviderFor(agentChatArchivedChats)
final agentChatArchivedChatsProvider = AgentChatArchivedChatsFamily._();

/// Chats of [workspaceId] that were closed; their history stays on the host
/// and Reopen brings one back in a new tab.

final class AgentChatArchivedChatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatSummary>>,
          List<AgentChatSummary>,
          FutureOr<List<AgentChatSummary>>
        >
    with
        $FutureModifier<List<AgentChatSummary>>,
        $FutureProvider<List<AgentChatSummary>> {
  /// Chats of [workspaceId] that were closed; their history stays on the host
  /// and Reopen brings one back in a new tab.
  AgentChatArchivedChatsProvider._({
    required AgentChatArchivedChatsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatArchivedChatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatArchivedChatsHash();

  @override
  String toString() {
    return r'agentChatArchivedChatsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatSummary>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return agentChatArchivedChats(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatArchivedChatsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatArchivedChatsHash() =>
    r'2cc94aa838c6b1971cf8310fe25bdfa228701d44';

/// Chats of [workspaceId] that were closed; their history stays on the host
/// and Reopen brings one back in a new tab.

final class AgentChatArchivedChatsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatSummary>>,
          (String, String)
        > {
  AgentChatArchivedChatsFamily._()
    : super(
        retry: null,
        name: r'agentChatArchivedChatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Chats of [workspaceId] that were closed; their history stays on the host
  /// and Reopen brings one back in a new tab.

  AgentChatArchivedChatsProvider call(String hostId, String workspaceId) =>
      AgentChatArchivedChatsProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'agentChatArchivedChatsProvider';
}

/// Providers the runtime can start a chat with in [workspaceId], with the
/// availability it verified on that host. Refreshed when the host reports a
/// provider change, so an open picker follows a Settings edit made anywhere.

@ProviderFor(agentChatProviders)
final agentChatProvidersProvider = AgentChatProvidersFamily._();

/// Providers the runtime can start a chat with in [workspaceId], with the
/// availability it verified on that host. Refreshed when the host reports a
/// provider change, so an open picker follows a Settings edit made anywhere.

final class AgentChatProvidersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatProviderInstance>>,
          List<AgentChatProviderInstance>,
          FutureOr<List<AgentChatProviderInstance>>
        >
    with
        $FutureModifier<List<AgentChatProviderInstance>>,
        $FutureProvider<List<AgentChatProviderInstance>> {
  /// Providers the runtime can start a chat with in [workspaceId], with the
  /// availability it verified on that host. Refreshed when the host reports a
  /// provider change, so an open picker follows a Settings edit made anywhere.
  AgentChatProvidersProvider._({
    required AgentChatProvidersFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatProvidersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatProvidersHash();

  @override
  String toString() {
    return r'agentChatProvidersProvider'
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
    final argument = this.argument as (String, String);
    return agentChatProviders(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatProvidersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatProvidersHash() =>
    r'8198183757760b43ec75303bfed3895925264bbb';

/// Providers the runtime can start a chat with in [workspaceId], with the
/// availability it verified on that host. Refreshed when the host reports a
/// provider change, so an open picker follows a Settings edit made anywhere.

final class AgentChatProvidersFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatProviderInstance>>,
          (String, String)
        > {
  AgentChatProvidersFamily._()
    : super(
        retry: null,
        name: r'agentChatProvidersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Providers the runtime can start a chat with in [workspaceId], with the
  /// availability it verified on that host. Refreshed when the host reports a
  /// provider change, so an open picker follows a Settings edit made anywhere.

  AgentChatProvidersProvider call(String hostId, String workspaceId) =>
      AgentChatProvidersProvider._(argument: (hostId, workspaceId), from: this);

  @override
  String toString() => r'agentChatProvidersProvider';
}

/// The chat preferences of one runtime: defaults for new chats and model
/// visibility. [remoteHostId] names a Remote Host behind the paired runtime,
/// whose chats follow its own preferences; null is the paired runtime.
/// Absent on a runtime without them, where defaults resolve from the catalog
/// alone and every model is shown.

@ProviderFor(agentChatPreferences)
final agentChatPreferencesProvider = AgentChatPreferencesFamily._();

/// The chat preferences of one runtime: defaults for new chats and model
/// visibility. [remoteHostId] names a Remote Host behind the paired runtime,
/// whose chats follow its own preferences; null is the paired runtime.
/// Absent on a runtime without them, where defaults resolve from the catalog
/// alone and every model is shown.

final class AgentChatPreferencesProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatPreferences?>,
          AgentChatPreferences?,
          FutureOr<AgentChatPreferences?>
        >
    with
        $FutureModifier<AgentChatPreferences?>,
        $FutureProvider<AgentChatPreferences?> {
  /// The chat preferences of one runtime: defaults for new chats and model
  /// visibility. [remoteHostId] names a Remote Host behind the paired runtime,
  /// whose chats follow its own preferences; null is the paired runtime.
  /// Absent on a runtime without them, where defaults resolve from the catalog
  /// alone and every model is shown.
  AgentChatPreferencesProvider._({
    required AgentChatPreferencesFamily super.from,
    required (String, String?) super.argument,
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
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatPreferences?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatPreferences?> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return agentChatPreferences(ref, argument.$1, argument.$2);
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
    r'3151f0caa1f7c2dcbbb88bb57d1b745497e3d351';

/// The chat preferences of one runtime: defaults for new chats and model
/// visibility. [remoteHostId] names a Remote Host behind the paired runtime,
/// whose chats follow its own preferences; null is the paired runtime.
/// Absent on a runtime without them, where defaults resolve from the catalog
/// alone and every model is shown.

final class AgentChatPreferencesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatPreferences?>,
          (String, String?)
        > {
  AgentChatPreferencesFamily._()
    : super(
        retry: null,
        name: r'agentChatPreferencesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The chat preferences of one runtime: defaults for new chats and model
  /// visibility. [remoteHostId] names a Remote Host behind the paired runtime,
  /// whose chats follow its own preferences; null is the paired runtime.
  /// Absent on a runtime without them, where defaults resolve from the catalog
  /// alone and every model is shown.

  AgentChatPreferencesProvider call(String hostId, String? remoteHostId) =>
      AgentChatPreferencesProvider._(
        argument: (hostId, remoteHostId),
        from: this,
      );

  @override
  String toString() => r'agentChatPreferencesProvider';
}
