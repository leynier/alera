import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_native_operation.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

enum AgentChatRewindMode(this.wire) {
  transcript('transcript'),
  native('native');

  final String wire;
}

enum AgentChatNativeHistoryAction(this.wire) {
  finishAcknowledged('finishAcknowledged'),
  restartFromTranscript('restartFromTranscript'),
  cancelUnstarted('cancelUnstarted'),
  continueFromCurrentFiles('continueFromCurrentFiles');

  final String wire;
}

/// Provider acknowledgement and observed filesystem effects are independent.
/// A successful native reply alone never claims that files were reverted.
class const AgentChatFilesystemRewindResult({
  final bool filesystemRewindAcknowledged = false,
  final bool? filesystemChangesReverted,
  final String? operationId,
  final AgentChatSnapshot? snapshot,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatFilesystemRewindResult(
      filesystemRewindAcknowledged: agentChatJsonBool(
        json['filesystemRewindAcknowledged'],
      ),
      filesystemChangesReverted: agentChatFilesystemEffectFromJson(
        json['filesystemChangesReverted'],
      ),
      operationId: agentChatJsonString(json['operationId']),
      snapshot: json['snapshot'] is Map
          ? AgentChatSnapshot.fromJson(json['snapshot'])
          : null,
    );
  }
}

/// The final host result of a durable operation, without native acknowledgement
/// envelopes, credentials, or provider-native identifiers.
class const AgentChatNativeOperationResult({
  final String? chatId,
  final String? tabId,
  final String? operationId,
  final String? operationKind,
  final AgentChatSnapshot? snapshot,
  final String? prompt,
  final List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
  final bool filesystemRewindAcknowledged = false,
  final bool? filesystemChangesReverted,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatNativeOperationResult(
      chatId: agentChatJsonString(json['chatId']),
      tabId: agentChatJsonString(json['tabId']),
      operationId: agentChatJsonString(json['operationId']),
      operationKind: agentChatJsonString(json['operationKind']),
      snapshot: json['snapshot'] is Map
          ? AgentChatSnapshot.fromJson(json['snapshot'])
          : null,
      prompt: agentChatJsonString(json['prompt']),
      attachments: List.unmodifiableOf(<AgentChatAttachment>[
        for (final attachment in agentChatJsonList(json['attachments']))
          if (attachment is Map) AgentChatAttachment.fromJson(attachment),
      ]),
      filesystemRewindAcknowledged: agentChatJsonBool(
        json['filesystemRewindAcknowledged'],
      ),
      filesystemChangesReverted: agentChatFilesystemEffectFromJson(
        json['filesystemChangesReverted'],
      ),
    );
  }
}

bool? agentChatFilesystemEffectFromJson(Object? value) =>
    value is bool ? value : null;

class const AgentChatNativeHistoryReconcileResult({
  required final AgentChatSnapshot snapshot,
  required final AgentChatNativeOperation operation,
  final AgentChatNativeOperationResult? result,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatNativeHistoryReconcileResult(
      snapshot: AgentChatSnapshot.fromJson(json['snapshot']),
      operation: AgentChatNativeOperation.fromJson(json['operation']),
      result: json['result'] is Map
          ? AgentChatNativeOperationResult.fromJson(json['result'])
          : null,
    );
  }
}
