import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_find_requests.g.dart';

/// A request to open find in one mounted chat. [serial] makes a repeated
/// request a new state, so pressing the chord again refocuses the field.
final class const AgentChatFindRequest({
  required final String chatId,
  required final int serial,
});

/// Find in Chat requests from the keyboard and the command palette. A chat
/// that is not mounted ignores them.
@Riverpod(keepAlive: true)
class AgentChatFindRequests extends _$AgentChatFindRequests {
  int _serial = 0;

  @override
  AgentChatFindRequest? build() => null;

  void open(String chatId) =>
      state = AgentChatFindRequest(chatId: chatId, serial: ++_serial);
}
