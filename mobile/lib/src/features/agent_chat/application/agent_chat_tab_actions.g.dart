// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_tab_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatTabActions)
final agentChatTabActionsProvider = AgentChatTabActionsFamily._();

final class AgentChatTabActionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTabActions>,
          AgentChatTabActions,
          FutureOr<AgentChatTabActions>
        >
    with
        $FutureModifier<AgentChatTabActions>,
        $FutureProvider<AgentChatTabActions> {
  AgentChatTabActionsProvider._({
    required AgentChatTabActionsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatTabActionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatTabActionsHash();

  @override
  String toString() {
    return r'agentChatTabActionsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatTabActions> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatTabActions> create(Ref ref) {
    final argument = this.argument as String;
    return agentChatTabActions(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatTabActionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatTabActionsHash() =>
    r'cd437cd33ffb6ad6636e78c5f7dca023ec4c3107';

final class AgentChatTabActionsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentChatTabActions>, String> {
  AgentChatTabActionsFamily._()
    : super(
        retry: null,
        name: r'agentChatTabActionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentChatTabActionsProvider call(String hostId) =>
      AgentChatTabActionsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentChatTabActionsProvider';
}
