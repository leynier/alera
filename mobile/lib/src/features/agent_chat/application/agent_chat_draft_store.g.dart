// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_draft_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatDraftStore)
final agentChatDraftStoreProvider = AgentChatDraftStoreProvider._();

final class AgentChatDraftStoreProvider
    extends
        $FunctionalProvider<
          AgentChatDraftStore,
          AgentChatDraftStore,
          AgentChatDraftStore
        >
    with $Provider<AgentChatDraftStore> {
  AgentChatDraftStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatDraftStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatDraftStoreHash();

  @$internal
  @override
  $ProviderElement<AgentChatDraftStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatDraftStore create(Ref ref) {
    return agentChatDraftStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatDraftStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatDraftStore>(value),
    );
  }
}

String _$agentChatDraftStoreHash() =>
    r'672af79f447211ba09f84b4db607f19f038fcbd6';
