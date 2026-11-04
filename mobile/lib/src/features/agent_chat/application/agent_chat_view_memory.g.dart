// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_view_memory.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatViewMemoryStore)
final agentChatViewMemoryStoreProvider = AgentChatViewMemoryStoreProvider._();

final class AgentChatViewMemoryStoreProvider
    extends
        $FunctionalProvider<
          AgentChatViewMemoryStore,
          AgentChatViewMemoryStore,
          AgentChatViewMemoryStore
        >
    with $Provider<AgentChatViewMemoryStore> {
  AgentChatViewMemoryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatViewMemoryStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatViewMemoryStoreHash();

  @$internal
  @override
  $ProviderElement<AgentChatViewMemoryStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatViewMemoryStore create(Ref ref) {
    return agentChatViewMemoryStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatViewMemoryStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatViewMemoryStore>(value),
    );
  }
}

String _$agentChatViewMemoryStoreHash() =>
    r'ea6e30da95f4d734fd82187792513d402dd9c492';
