import 'dart:collection';

import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_timeline_sessions.g.dart';

/// How a chat's timeline reacts to new output.
enum AgentChatScrollMode {
  /// Pinned to the end: new output scrolls into view.
  following,

  /// A message was just sent: its prompt stays near the top while the agent
  /// starts, so the person reads the answer from its beginning. Ends when
  /// tool activity starts or the reader scrolls.
  anchoring,

  /// The reader scrolled away; nothing moves under them.
  free,
}

/// Where the reader was in one chat, which rows they opened or closed, and
/// which requests they have seen. Lives for the app session only, so a tab switch or a pane move restores
/// it; it is never persisted.
final class AgentChatTimelineSession {
  final AgentChatExpansion expansion = AgentChatExpansion();
  AgentChatScrollMode mode = AgentChatScrollMode.following;

  /// In [AgentChatScrollMode.free], the timeline entry at the top of the
  /// viewport and how far its top sat below the viewport top.
  String? anchorKey;
  double anchorOffset = 0;

  /// Scroll offset at the last save, used when [anchorKey] is gone.
  double? pixels;

  /// In [AgentChatScrollMode.anchoring], the entry whose top is pinned, and
  /// the client message id that lets the anchor follow an optimistic message
  /// into the turn the runtime stamps it into.
  String? anchoredEntryKey;
  String? anchoredClientMessageId;

  /// Requests the request dock has already shown, so a remounted dock does
  /// not take the focus again for a request that was there before.
  final Set<String> seenRequestIds = <String>{};
}

/// Per-chat timeline sessions, most recently used last. Bounded, because a
/// person may open and close many chats in one app session and each entry
/// only matters while its tab could come back.
final class AgentChatTimelineSessions {
  static const int limit = 64;

  final LinkedHashMap<String, AgentChatTimelineSession> _sessions =
      LinkedHashMap<String, AgentChatTimelineSession>();

  AgentChatTimelineSession of(String chatId) {
    final session = _sessions.remove(chatId) ?? AgentChatTimelineSession();
    _sessions[chatId] = session;
    while (_sessions.length > limit) {
      _sessions.remove(_sessions.keys.first);
    }
    return session;
  }

  void forget(String chatId) => _sessions.remove(chatId);

  int get length => _sessions.length;
}

@Riverpod(keepAlive: true)
AgentChatTimelineSessions agentChatTimelineSessions(Ref ref) =>
    AgentChatTimelineSessions();
