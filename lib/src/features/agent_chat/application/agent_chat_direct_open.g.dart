// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_direct_open.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// New Agent Chat without a dialog: the chat starts with the resolved agent
/// and model and opens in the target pane with its composer focused. Only
/// one open per workspace runs at a time, and a failed create keeps its
/// request id so the next attempt cannot duplicate the chat on the runtime.

@ProviderFor(agentChatDirectOpener)
final agentChatDirectOpenerProvider = AgentChatDirectOpenerProvider._();

/// New Agent Chat without a dialog: the chat starts with the resolved agent
/// and model and opens in the target pane with its composer focused. Only
/// one open per workspace runs at a time, and a failed create keeps its
/// request id so the next attempt cannot duplicate the chat on the runtime.

final class AgentChatDirectOpenerProvider
    extends
        $FunctionalProvider<
          AgentChatDirectOpener,
          AgentChatDirectOpener,
          AgentChatDirectOpener
        >
    with $Provider<AgentChatDirectOpener> {
  /// New Agent Chat without a dialog: the chat starts with the resolved agent
  /// and model and opens in the target pane with its composer focused. Only
  /// one open per workspace runs at a time, and a failed create keeps its
  /// request id so the next attempt cannot duplicate the chat on the runtime.
  AgentChatDirectOpenerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatDirectOpenerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatDirectOpenerHash();

  @$internal
  @override
  $ProviderElement<AgentChatDirectOpener> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatDirectOpener create(Ref ref) {
    return agentChatDirectOpener(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatDirectOpener value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatDirectOpener>(value),
    );
  }
}

String _$agentChatDirectOpenerHash() =>
    r'70966d007f9c17e070873e6371eb5f5656c4011c';
