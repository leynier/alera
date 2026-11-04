// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_request_ids.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatRequestIds)
final agentChatRequestIdsProvider = AgentChatRequestIdsProvider._();

final class AgentChatRequestIdsProvider
    extends
        $FunctionalProvider<
          AgentChatRequestIds,
          AgentChatRequestIds,
          AgentChatRequestIds
        >
    with $Provider<AgentChatRequestIds> {
  AgentChatRequestIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatRequestIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatRequestIdsHash();

  @$internal
  @override
  $ProviderElement<AgentChatRequestIds> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatRequestIds create(Ref ref) {
    return agentChatRequestIds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatRequestIds value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatRequestIds>(value),
    );
  }
}

String _$agentChatRequestIdsHash() =>
    r'ba21d67140fa6cd5dc2086f42f8410346768cd67';
