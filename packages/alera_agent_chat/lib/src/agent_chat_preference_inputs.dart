import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_preferences.dart';
import 'package:alera_agent_chat/src/agent_chat_selection.dart';

sealed class AgentChatPreferenceOperation {
  const AgentChatPreferenceOperation();

  AgentChatJson toJson();
}

final class const AgentChatSetDefaultSelection(
  final AgentChatSelection? selection,
) extends AgentChatPreferenceOperation {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'setDefaultSelection',
    'selection': selection?.toJson(),
  };
}

final class const AgentChatSetProjectDefault({
  required final String projectId,
  required final AgentChatSelection? selection,
}) extends AgentChatPreferenceOperation {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'setProjectDefault',
    'projectId': projectId,
    'selection': selection?.toJson(),
  };
}

final class const AgentChatSetModelPreferences({
  required final String providerInstanceId,
  required final AgentChatModelPreferences preferences,
}) extends AgentChatPreferenceOperation {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'setModels',
    'providerInstanceId': providerInstanceId,
    ...preferences.toJson(),
  };
}

final class const AgentChatSetFavorites(
  final List<AgentChatSelection> favorites,
) extends AgentChatPreferenceOperation {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'type': 'setFavorites',
    'favorites': <AgentChatJson>[
      for (final favorite in favorites)
        <String, Object?>{
          'providerInstanceId': favorite.providerInstanceId,
          'model': agentChatJsonString(favorite.model),
        },
    ],
  };
}

class const AgentChatPreferencesUpdate({
  required final String requestId,
  required final int expectedRevision,
  required final List<AgentChatPreferenceOperation> operations,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'operations': <AgentChatJson>[
      for (final operation in operations) operation.toJson(),
    ],
  };
}
