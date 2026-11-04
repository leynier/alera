// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_timeline_sessions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatTimelineSessions)
final agentChatTimelineSessionsProvider = AgentChatTimelineSessionsProvider._();

final class AgentChatTimelineSessionsProvider
    extends
        $FunctionalProvider<
          AgentChatTimelineSessions,
          AgentChatTimelineSessions,
          AgentChatTimelineSessions
        >
    with $Provider<AgentChatTimelineSessions> {
  AgentChatTimelineSessionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatTimelineSessionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatTimelineSessionsHash();

  @$internal
  @override
  $ProviderElement<AgentChatTimelineSessions> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatTimelineSessions create(Ref ref) {
    return agentChatTimelineSessions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatTimelineSessions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatTimelineSessions>(value),
    );
  }
}

String _$agentChatTimelineSessionsHash() =>
    r'982d7f1fa08cd73f63944889a47479a7073ea1f6';
