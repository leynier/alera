// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_find_requests.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Find in Chat requests from the keyboard and the command palette. A chat
/// that is not mounted ignores them.

@ProviderFor(AgentChatFindRequests)
final agentChatFindRequestsProvider = AgentChatFindRequestsProvider._();

/// Find in Chat requests from the keyboard and the command palette. A chat
/// that is not mounted ignores them.
final class AgentChatFindRequestsProvider
    extends $NotifierProvider<AgentChatFindRequests, AgentChatFindRequest?> {
  /// Find in Chat requests from the keyboard and the command palette. A chat
  /// that is not mounted ignores them.
  AgentChatFindRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatFindRequestsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatFindRequestsHash();

  @$internal
  @override
  AgentChatFindRequests create() => AgentChatFindRequests();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatFindRequest? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatFindRequest?>(value),
    );
  }
}

String _$agentChatFindRequestsHash() =>
    r'a054dcf30a0f003f7dd0e9b52278692152365c9b';

/// Find in Chat requests from the keyboard and the command palette. A chat
/// that is not mounted ignores them.

abstract class _$AgentChatFindRequests
    extends $Notifier<AgentChatFindRequest?> {
  AgentChatFindRequest? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentChatFindRequest?, AgentChatFindRequest?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentChatFindRequest?, AgentChatFindRequest?>,
              AgentChatFindRequest?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
