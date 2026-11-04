import 'package:alera_agent_chat/src/agent_chat_change.dart';
import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';

const String _alera = 'alera';

/// The Alera chat tool an item calls, across the names providers give it:
/// `mcp__alera__chat_task_wait` (Claude), `chat_task_wait` on server
/// `alera` (Codex), `alera_chat_task_wait` (ACP agents), or Cursor's
/// envelope that names the server and tool in its input.
String? agentChatAleraToolName(AgentChatItem item) {
  final name = item.toolName?.trim();
  if (name == null || name.isEmpty) return null;
  if (item.server == _alera) return name;
  for (final prefix in const <String>['mcp__alera__', 'alera_', 'alera-']) {
    if (name.startsWith(prefix)) return name.substring(prefix.length);
  }
  final input = item.input;
  if (input is Map) {
    final server = input['providerIdentifier'] ?? input['server'];
    final tool = input['toolName'] ?? input['name'];
    if (server == _alera && tool is String) return tool;
  }
  return null;
}

/// The call's own arguments, inside Cursor's envelope when it has one.
Map<String, Object?> _arguments(AgentChatItem item) {
  final input = agentChatJsonMap(item.input);
  final nested = input['args'] ?? input['arguments'];
  return nested is Map ? agentChatJsonMap(nested) : input;
}

/// Whether [item] waits on delegated tasks: `chat_task_wait`, or a
/// `chat_delegate` with `mode: wait`.
bool agentChatIsTaskWaitCall(AgentChatItem item) =>
    switch (agentChatAleraToolName(item)) {
      'chat_task_wait' => true,
      'chat_delegate' => _arguments(item)['mode'] == 'wait',
      _ => false,
    };

bool _executes(AgentChatItem item) =>
    item.type.isActivity &&
    item.type != AgentChatItemType.reviewEntered &&
    item.type != AgentChatItemType.reviewExited;

/// Whether a running chat only waits on its delegated tasks: its turn runs,
/// and every execution item still in progress in it is such a wait.
bool agentChatBlockedOnTaskWait(
  AgentChatSession session,
  Iterable<AgentChatItem> items,
) {
  final turn = session.activeTurnId;
  if (turn == null) return false;
  var waits = false;
  for (final item in items) {
    if (item.turnId != turn ||
        item.status != AgentChatItemStatus.inProgress ||
        !_executes(item)) {
      continue;
    }
    if (!agentChatIsTaskWaitCall(item)) return false;
    waits = true;
  }
  return waits;
}

/// Keeps [agentChatBlockedOnTaskWait] for many chats from their
/// `agentChatChanged` deltas, without their transcripts: only the execution
/// items in progress in each chat's active turn.
final class AgentChatTaskWaitFold {
  final Map<String, String?> _turns = <String, String?>{};
  final Map<String, Map<String, AgentChatItem>> _running =
      <String, Map<String, AgentChatItem>>{};

  /// Folds [change]; true when the chat's blocked state changed.
  bool apply(AgentChatChange change) {
    final before = blocked(change.chatId);
    final session = change.session;
    if (session != null) {
      _turns[change.chatId] = session.activeTurnId;
      if (session.activeTurnId == null) _running.remove(change.chatId);
    }
    for (final item in change.items) {
      if (!_executes(item)) continue;
      final running = _running.putIfAbsent(change.chatId, () => {});
      if (item.status == AgentChatItemStatus.inProgress) {
        running[item.id] = item;
      } else {
        running.remove(item.id);
      }
    }
    for (final id in change.removedItemIds) {
      _running[change.chatId]?.remove(id);
    }
    return blocked(change.chatId) != before;
  }

  /// Whether [chatId] only waits on its delegated tasks, as far as the
  /// changes seen since [forget] show.
  bool blocked(String chatId) {
    final turn = _turns[chatId];
    final running = _running[chatId];
    if (turn == null || running == null) return false;
    return agentChatBlockedOnTaskWait(
      AgentChatSession(activeTurnId: turn),
      running.values,
    );
  }

  /// Drops what is known of [chatId], or of every chat.
  void forget([String? chatId]) {
    if (chatId == null) {
      _turns.clear();
      _running.clear();
    } else {
      _turns.remove(chatId);
      _running.remove(chatId);
    }
  }
}
