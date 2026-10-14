import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// Fixed public recovery metadata. Native acknowledgements, errors, and
/// provider-native identifiers never enter this projection.
class const AgentChatNativeOperationRecovery({
  final bool needsReconciliation = false,
  final bool canCancelUnstarted = false,
  final bool canFinishAcknowledged = false,
  final bool canRestartFromTranscript = false,
  final bool canContinueFromCurrentFiles = false,
  final String message = '',
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatNativeOperationRecovery(
      needsReconciliation: agentChatJsonBool(json['needsReconciliation']),
      canCancelUnstarted: agentChatJsonBool(json['canCancelUnstarted']),
      canFinishAcknowledged: agentChatJsonBool(json['canFinishAcknowledged']),
      canRestartFromTranscript: agentChatJsonBool(
        json['canRestartFromTranscript'],
      ),
      canContinueFromCurrentFiles: agentChatJsonBool(
        json['canContinueFromCurrentFiles'],
      ),
      message: agentChatJsonText(json['message']),
    );
  }

  AgentChatJson toJson() => <String, Object?>{
    'needsReconciliation': needsReconciliation,
    'canCancelUnstarted': canCancelUnstarted,
    'canFinishAcknowledged': canFinishAcknowledged,
    'canRestartFromTranscript': canRestartFromTranscript,
    'canContinueFromCurrentFiles': canContinueFromCurrentFiles,
    'message': message,
  };
}

class const AgentChatNativeOperation({
  required final String operationId,
  required final String state,
  required final String kind,
  final AgentChatNativeOperationRecovery? recovery,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['operationId']);
    if (id == null)
      throw const FormatException('Native operation has no operationId.');
    return AgentChatNativeOperation(
      operationId: id,
      state: agentChatJsonText(json['state']),
      kind: agentChatJsonText(json['kind']),
      recovery: json['recovery'] is Map
          ? AgentChatNativeOperationRecovery.fromJson(json['recovery'])
          : null,
    );
  }

  AgentChatJson toJson() => <String, Object?>{
    'operationId': operationId,
    'state': state,
    'kind': kind,
    'recovery': ?recovery?.toJson(),
  };
}

AgentChatNativeOperation? agentChatPendingNativeOperationFromJson(
  Object? value,
) {
  if (value == null) return null;
  if (value is! Map)
    throw const FormatException('Invalid pending native operation.');
  return AgentChatNativeOperation.fromJson(value);
}
