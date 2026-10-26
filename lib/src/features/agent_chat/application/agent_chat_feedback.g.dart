// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_feedback.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The `/feedback` submissions of each chat, by chat id, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the chat tab so a hidden tab still finishes.

@ProviderFor(AgentChatFeedbackSubmissions)
final agentChatFeedbackSubmissionsProvider =
    AgentChatFeedbackSubmissionsProvider._();

/// The `/feedback` submissions of each chat, by chat id, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the chat tab so a hidden tab still finishes.
final class AgentChatFeedbackSubmissionsProvider
    extends
        $NotifierProvider<
          AgentChatFeedbackSubmissions,
          Map<String, List<AgentChatFeedbackSubmission>>
        > {
  /// The `/feedback` submissions of each chat, by chat id, for this app
  /// session. T3 Code keeps them on the client too: the upload does not change
  /// the conversation, so the runtime transcript never holds them. A chat is
  /// claimed from the consent dialog until its upload ends, so one runs at a
  /// time, and the store outlives the chat tab so a hidden tab still finishes.
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
    r'33c6ed446adc5a0c324c58db04d4429b16d74a26';

/// The `/feedback` submissions of each chat, by chat id, for this app
/// session. T3 Code keeps them on the client too: the upload does not change
/// the conversation, so the runtime transcript never holds them. A chat is
/// claimed from the consent dialog until its upload ends, so one runs at a
/// time, and the store outlives the chat tab so a hidden tab still finishes.

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
