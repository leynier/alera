// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_task_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatTaskActions)
final chatTaskActionsProvider = ChatTaskActionsProvider._();

final class ChatTaskActionsProvider
    extends
        $FunctionalProvider<
          AgentChatTaskActions,
          AgentChatTaskActions,
          AgentChatTaskActions
        >
    with $Provider<AgentChatTaskActions> {
  ChatTaskActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskActionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskActionsHash();

  @$internal
  @override
  $ProviderElement<AgentChatTaskActions> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatTaskActions create(Ref ref) {
    return chatTaskActions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatTaskActions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatTaskActions>(value),
    );
  }
}

String _$chatTaskActionsHash() => r'bfeeda442646ee8002733dbf9504fc41837ed9fb';
