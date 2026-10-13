import 'package:alera/src/features/agent_chat/domain/agent_chat_tab_activity.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a pending request or a waiting session needs the person', () {
    expect(
      agentChatTabActivity(
        AgentChatSessionStatus.running,
        hasPendingRequests: true,
      ),
      AgentChatTabActivity.needsInput,
    );
    expect(
      agentChatTabActivity(AgentChatSessionStatus.waiting),
      AgentChatTabActivity.needsInput,
    );
    expect(
      agentChatTabActivity(AgentChatSessionStatus.running),
      AgentChatTabActivity.working,
    );
    expect(
      agentChatTabActivity(AgentChatSessionStatus.error),
      AgentChatTabActivity.failed,
    );
    expect(
      agentChatTabActivity(AgentChatSessionStatus.ready),
      AgentChatTabActivity.idle,
    );
  });

  test('changes fold into the last known chat state', () {
    const start = (
      status: AgentChatSessionStatus.running,
      hasPendingRequests: false,
    );
    final withRequest = agentChatFoldChange(
      start,
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 2,
        'delta': <String, Object?>{
          'requests': <Object?>[
            <String, Object?>{
              'requestId': 'r1',
              'kind': 'file_change_approval',
              'createdAt': '2026-10-12T10:00:00Z',
            },
          ],
        },
      }),
    );
    expect(withRequest.hasPendingRequests, isTrue);
    expect(withRequest.status, AgentChatSessionStatus.running);
    final textOnly = agentChatFoldChange(
      withRequest,
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 3,
        'delta': <String, Object?>{
          'textAppends': <Object?>[
            <String, Object?>{
              'itemId': 'a',
              'stream': 'text',
              'offset': 0,
              'text': 'x',
            },
          ],
        },
      }),
    );
    expect(textOnly, withRequest);
    final settled = agentChatFoldChange(
      textOnly,
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 4,
        'delta': <String, Object?>{
          'requests': <Object?>[],
          'session': <String, Object?>{'status': 'ready'},
        },
      }),
    );
    expect(
      agentChatTabActivity(
        settled.status,
        hasPendingRequests: settled.hasPendingRequests,
      ),
      AgentChatTabActivity.idle,
    );
  });
}
