import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

/// `agentChat.create`. [requestId] makes a retried create return the same
/// chat instead of a second one. [providerInstanceId] defaults to the
/// provider's default instance on the runtime.
class const AgentChatCreateInput({
  required final String requestId,
  required final String workspaceId,
  final String? provider,
  final String? providerInstanceId,
  final String? model,
  final String? reasoningEffort,
  final AgentChatRuntimeMode? runtimeMode,
  final AgentChatInteractionMode? interactionMode,
  final String? title,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'requestId': requestId,
    'workspaceId': workspaceId,
    'provider': ?provider,
    'providerInstanceId': ?providerInstanceId,
    'model': ?agentChatJsonString(model),
    'reasoningEffort': ?agentChatJsonString(reasoningEffort),
    'runtimeMode': ?runtimeMode?.wire,
    'interactionMode': ?interactionMode?.wire,
    'title': ?title,
  };
}

/// The answer of `agentChat.create` and `agentChat.reopen`.
class const AgentChatOpenResult({
  required final String chatId,
  required final AgentChatSnapshot snapshot,
  final String? tabId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final snapshot = AgentChatSnapshot.fromJson(json['snapshot']);
    return AgentChatOpenResult(
      chatId: agentChatJsonString(json['chatId']) ?? snapshot.chatId,
      tabId: agentChatJsonString(json['tabId']) ?? snapshot.tabId,
      snapshot: snapshot,
    );
  }
}

/// `agentChat.send`. [clientMessageId] is the idempotency key and the id the
/// runtime stamps on the resulting user message or queue entry, so the client
/// can replace its optimistic copy with the real one.
class const AgentChatSendInput({
  required final String chatId,
  required final String workspaceId,
  required final String clientMessageId,
  required final String text,
  final List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
  final String? model,
  final String? reasoningEffort,
  final AgentChatInteractionMode? interactionMode,
  final AgentChatDelivery delivery = AgentChatDelivery.auto,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'requestId': clientMessageId,
    'clientMessageId': clientMessageId,
    'chatId': chatId,
    'workspaceId': workspaceId,
    'text': text,
    if (attachments.isNotEmpty)
      'attachments': <AgentChatJson>[
        for (final attachment in attachments) attachment.toJson(),
      ],
    'model': ?agentChatJsonString(model),
    'reasoningEffort': ?agentChatJsonString(reasoningEffort),
    'interactionMode': ?interactionMode?.wire,
    'delivery': delivery.wire,
  };
}

/// What the runtime did with a sent message.
enum AgentChatSendDelivery {
  started,
  queued,
  steered;

  static AgentChatSendDelivery fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatSendDelivery.values,
    AgentChatSendDelivery.started,
  );
}

class const AgentChatSendResult({
  required final AgentChatSendDelivery delivery,
  final String? itemId,
  final String? turnId,
  final String? queueId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatSendResult(
      delivery: AgentChatSendDelivery.fromJson(json['delivery']),
      itemId: agentChatJsonString(json['itemId']),
      turnId: agentChatJsonString(json['turnId']),
      queueId: agentChatJsonString(json['queueId']),
    );
  }
}

/// The answer to an [AgentChatRequest], mirroring the provider protocol's
/// runtime response.
sealed class AgentChatResponse {
  const AgentChatResponse();

  AgentChatJson toJson();
}

final class AgentChatApprovalResponse extends AgentChatResponse {
  const AgentChatApprovalResponse(this.decision, {this.feedback});

  final AgentChatApprovalDecision decision;

  /// What to tell the agent with a decline, when the request supports it.
  final String? feedback;

  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'approval',
    'decision': decision.wire,
    'feedback': ?feedback,
  };
}

/// Answers keyed by question id. Each list holds the selected options' answer
/// values followed by any custom text; an empty map skips the questions.
final class AgentChatUserInputResponse extends AgentChatResponse {
  const AgentChatUserInputResponse(this.answers);

  final Map<String, List<String>> answers;

  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'userInput',
    'answers': <String, Object?>{
      for (final entry in answers.entries) entry.key: entry.value,
    },
  };
}

final class AgentChatElicitationResponse extends AgentChatResponse {
  const AgentChatElicitationResponse(this.action, [this.content]);

  final AgentChatElicitationAction action;
  final AgentChatJson? content;

  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'elicitation',
    'action': action.wire,
    'content': ?content,
  };
}

/// `agentChat.configure`: settings for the chat's next turn; only present
/// fields change. Another [provider] or [providerInstanceId] moves the chat,
/// with its history, to a new session of that provider; the runtime refuses
/// it (`turnActive`) while a turn, a request, or queued work is open.
class const AgentChatConfiguration({
  final String? provider,
  final String? providerInstanceId,
  final String? model,
  final bool resetModel = false,
  final String? reasoningEffort,
  final bool resetReasoningEffort = false,
  final AgentChatRuntimeMode? runtimeMode,
  final AgentChatInteractionMode? interactionMode,
}) {
  bool get isEmpty =>
      provider == null &&
      providerInstanceId == null &&
      model == null &&
      !resetModel &&
      reasoningEffort == null &&
      !resetReasoningEffort &&
      runtimeMode == null &&
      interactionMode == null;

  bool get switchesProvider => provider != null || providerInstanceId != null;

  AgentChatJson toJson() => <String, Object?>{
    'provider': ?provider,
    'providerInstanceId': ?providerInstanceId,
    if (resetModel || model != null) 'model': agentChatJsonString(model),
    if (resetReasoningEffort || reasoningEffort != null)
      'reasoningEffort': agentChatJsonString(reasoningEffort),
    'runtimeMode': ?runtimeMode?.wire,
    'interactionMode': ?interactionMode?.wire,
  };
}
