import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String text = '',
  String status = 'completed',
  String createdAt = '2026-10-12T10:00:00Z',
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': 'turn-1',
  'type': type,
  'status': status,
  'createdAt': createdAt,
  'updatedAt': createdAt,
  'text': text,
  'normalized': normalized,
};

Map<String, Object?> _command(String id) => _item(
  id,
  'command_execution',
  normalized: <String, Object?>{'command': 'step $id'},
);

AgentChatTurnSection _section(List<Map<String, Object?>> items) =>
    AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'session': <String, Object?>{'status': 'idle'},
          'items': items,
        }),
      ),
    ).entries.whereType<AgentChatTurnEntry>().single.section;

Future<void> _pump(WidgetTester tester, AgentChatTurnSection section) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: AgentChatScope(
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
    );

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.textContaining(text, findRichText: true)).dy;

Map<String, Object?> _handoff({required bool failed}) => _item(
  'h1',
  'notice',
  status: failed ? 'failed' : 'completed',
  normalized: <String, Object?>{
    'handoff': <String, Object?>{
      'from': <String, Object?>{'provider': 'codex', 'model': 'gpt-5'},
      'to': <String, Object?>{'provider': 'claudeAgent'},
      'status': failed ? 'failed' : 'completed',
    },
  },
);

void main() {
  testWidgets('a steer sits between the work it split and folds its own', (
    tester,
  ) async {
    await _pump(
      tester,
      _section(<Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Start'),
        _command('c1'),
        _command('c2'),
        _item('a1', 'assistant_message', text: 'First pass'),
        _item(
          'u2',
          'user_message',
          text: 'Also add tests',
          createdAt: '2026-10-12T10:00:10Z',
        ),
        _command('c3'),
        _command('c4'),
        _command('c5'),
        _item(
          'a2',
          'assistant_message',
          text: 'Second pass',
          createdAt: '2026-10-12T10:00:40Z',
        ),
      ]),
    );
    expect(find.text('Worked for 40s'), findsOneWidget);
    expect(find.text('Continued for 30s'), findsOneWidget);
    expect(
      _top(tester, 'First pass'),
      lessThan(_top(tester, 'Also add tests')),
    );
    expect(
      _top(tester, 'Also add tests'),
      lessThan(_top(tester, 'Continued for 30s')),
    );
    expect(
      _top(tester, 'Continued for 30s'),
      lessThan(_top(tester, 'Second pass')),
    );

    expect(find.textContaining('3 commands'), findsNothing);
    await tester.tap(find.text('Continued for 30s'));
    await tester.pump();
    expect(find.textContaining('3 commands'), findsOneWidget);
    expect(find.textContaining('2 commands'), findsNothing);
  });

  testWidgets('a handoff draws a divider above its turn', (tester) async {
    await _pump(
      tester,
      _section(<Map<String, Object?>>[
        _handoff(failed: false),
        _item('u1', 'user_message', text: 'Continue here'),
        _item('a1', 'assistant_message', text: 'On it'),
      ]),
    );
    expect(find.text('Context Handoff'), findsOneWidget);
    expect(find.text('gpt-5'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Context handoff'), findsNothing);
    expect(
      _top(tester, 'Context Handoff'),
      lessThan(_top(tester, 'Continue here')),
    );
    expect(
      find.bySemanticsLabel('Context Handoff from gpt-5 to Claude'),
      findsOneWidget,
    );
  });

  testWidgets('a failed handoff reads as failed', (tester) async {
    await _pump(
      tester,
      _section(<Map<String, Object?>>[
        _handoff(failed: true),
        _item('u1', 'user_message', text: 'Continue here'),
      ]),
    );
    final label = tester.widget<Text>(find.text('Context Handoff Failed'));
    expect(label.style?.color, AleraTokens.error);
  });
}
