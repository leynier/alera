import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('a chat link names the chat and its workspace', () {
    final ref = agentChatRefFromLink(
      'alera-chat://v1/chat-1?workspace=ws%2F1',
    )!;
    expect(ref.chatId, 'chat-1');
    expect(ref.workspaceId, 'ws/1');
  });

  test('other links and chat links without a workspace are not chats', () {
    for (final link in <String>[
      'https://example.com',
      'alera-chat://v1/chat-1',
      'alera-chat://v2/chat-1?workspace=w',
      'alera-chat://v1/?workspace=w',
      'notes.md:12',
    ]) {
      expect(agentChatRefFromLink(link), isNull, reason: link);
    }
  });
}
