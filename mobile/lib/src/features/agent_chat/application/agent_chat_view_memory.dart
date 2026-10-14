import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_view_memory.g.dart';

/// Within this distance of the newest message the transcript follows new
/// output; further up, the reader has chosen a place and keeps it.
const double agentChatFollowThreshold = 40;

/// How one chat was left on screen: where the reader scrolled to and which
/// folds they opened or closed by hand. Session state only, never synced: the
/// same chat on the desktop keeps its own place.
class AgentChatViewMemory {
  double _scrollOffset = 0;
  final Map<String, bool> _expansions = <String, bool>{};

  /// Distance from the newest message, in the reversed list's own units.
  double get scrollOffset => _scrollOffset;

  /// Following re-arms once the reader comes back near the newest message.
  bool get following => _scrollOffset <= agentChatFollowThreshold;

  void rememberScroll(double offset) => _scrollOffset = offset < 0 ? 0 : offset;

  /// The person's own choice for a fold, or null while the default applies.
  bool? expansion(String key) => _expansions[key];

  void rememberExpansion(String key, {required bool expanded}) =>
      _expansions[key] = expanded;
}

/// Per host and chat, so switching tabs or rebuilding the connection brings a
/// chat back where it was left.
class AgentChatViewMemoryStore {
  final Map<({String hostId, String chatId}), AgentChatViewMemory> _chats =
      <({String hostId, String chatId}), AgentChatViewMemory>{};

  AgentChatViewMemory of(String hostId, String chatId) => _chats.putIfAbsent((
    hostId: hostId,
    chatId: chatId,
  ), AgentChatViewMemory.new);

  /// A closed or discarded chat has nothing left to restore.
  void forget(String hostId, String chatId) =>
      _chats.remove((hostId: hostId, chatId: chatId));
}

@Riverpod(keepAlive: true)
AgentChatViewMemoryStore agentChatViewMemoryStore(Ref ref) =>
    AgentChatViewMemoryStore();
