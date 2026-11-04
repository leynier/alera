// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_feedback.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The `/feedback` submissions of each chat, by host and chat, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the tab, which a host reconnect can rebuild
/// while the upload is still waiting on its answer.

@ProviderFor(AgentChatFeedbackSubmissions)
final agentChatFeedbackSubmissionsProvider =
    AgentChatFeedbackSubmissionsProvider._();

/// The `/feedback` submissions of each chat, by host and chat, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the tab, which a host reconnect can rebuild
/// while the upload is still waiting on its answer.
final class AgentChatFeedbackSubmissionsProvider
    extends
        $NotifierProvider<
          AgentChatFeedbackSubmissions,
          Map<String, List<AgentChatFeedbackSubmission>>
        > {
  /// The `/feedback` submissions of each chat, by host and chat, for this app
  /// session. T3 Code keeps them on the client too: the upload does not change
  /// the conversation, so the runtime transcript never holds them. A chat is
  /// claimed from the consent dialog until its upload ends, so one runs at a
  /// time, and the store outlives the tab, which a host reconnect can rebuild
  /// while the upload is still waiting on its answer.
  AgentChatFeedbackSubmissionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatFeedbackSubmissionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatFeedbackSubmissionsHash();

  @$internal
  @override
  AgentChatFeedbackSubmissions create() => AgentChatFeedbackSubmissions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    Map<String, List<AgentChatFeedbackSubmission>> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Map<String, List<AgentChatFeedbackSubmission>>>(
            value,
          ),
    );
  }
}

String _$agentChatFeedbackSubmissionsHash() =>
    r'0ac9c07e6f09076477cefc1649e5511916b086d6';

/// The `/feedback` submissions of each chat, by host and chat, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the tab, which a host reconnect can rebuild
/// while the upload is still waiting on its answer.

abstract class _$AgentChatFeedbackSubmissions
    extends $Notifier<Map<String, List<AgentChatFeedbackSubmission>>> {
  Map<String, List<AgentChatFeedbackSubmission>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, List<AgentChatFeedbackSubmission>>,
              Map<String, List<AgentChatFeedbackSubmission>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, List<AgentChatFeedbackSubmission>>,
                Map<String, List<AgentChatFeedbackSubmission>>
              >,
              Map<String, List<AgentChatFeedbackSubmission>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
