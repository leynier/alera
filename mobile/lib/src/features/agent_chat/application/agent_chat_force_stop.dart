import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Whether the composer offers Force stop for [view]: the runtime supports
/// it ([supported], `agentChatForceStopV1`) and marked the running turn's
/// Stop unresponsive.
bool agentChatOffersForceStop(
  AgentChatViewState view, {
  required bool supported,
}) => supported && view.turnActive && view.session.stopUnresponsive;

/// Ends the running turn of an agent that ignored Stop by stopping its
/// process; the turn's end arrives as a change.
Future<void> forceStopAgentChat(
  AgentChatRepository repository,
  AgentChatViewState view,
) async {
  await repository.lifecycle.forceStop(
    view.ref,
    requestId: _uuid.v4(),
    turnId: view.session.activeTurnId,
  );
}
