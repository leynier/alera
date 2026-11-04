import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(String id, String type, String status) =>
    <String, Object?>{
      'itemId': id,
      'turnId': 'turn-1',
      'type': type,
      'status': status,
      'createdAt': '2026-10-12T10:00:00Z',
      'updatedAt': '2026-10-12T10:00:00Z',
      'text': '',
      'normalized': type == 'command_execution'
          ? <String, Object?>{'command': 'step $id'}
          : const <String, Object?>{},
    };

AgentChatTurnSection _section(String compaction) =>
    AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'session': <String, Object?>{
            'status': 'running',
            'activeTurnId': 'turn-1',
          },
          'items': <Object?>[
            _item('c1', 'command_execution', 'completed'),
            _item('k1', 'context_compaction', compaction),
          ],
        }),
      ),
    ).entries.whereType<AgentChatTurnEntry>().single.section;

Future<void> _pump(WidgetTester tester, AgentChatTurnSection section) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: AgentChatElapsedClock(
            now: () => DateTime.utc(2026, 10, 12, 10, 0, 12),
            child: AgentChatScope(
              hostId: 'host-1',
              workspaceId: 'ws-1',
              chatId: 'chat-1',
              cwd: '/work',
              memory: AgentChatViewMemory(),
              child: SingleChildScrollView(
                child: AgentChatTurnView(section: section),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a running compaction times itself in the live row', (
    tester,
  ) async {
    await _pump(tester, _section('inProgress'));
    expect(find.text('Compacting for 12s'), findsOneWidget);
    await _pump(tester, _section('completed'));
    expect(find.textContaining('Compacting for'), findsNothing);
  });
}
