import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String text = '',
  String status = 'completed',
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': 'turn-1',
  'type': type,
  'status': status,
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'text': text,
  'normalized': normalized,
};

Map<String, Object?> _command(String id, {String status = 'completed'}) =>
    _item(
      id,
      'command_execution',
      status: status,
      normalized: <String, Object?>{'command': 'step $id'},
    );

AgentChatTurnSection _section(
  List<Map<String, Object?>> items, {
  Map<String, Object?>? turn,
  bool running = false,
}) => AgentChatTimelineProjection.build(
  AgentChatThread.fromSnapshot(
    AgentChatSnapshot.fromJson(<String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'cursor': 1,
      'session': <String, Object?>{
        'status': running ? 'running' : 'idle',
        if (running) 'activeTurnId': 'turn-1',
      },
      'turns': <Object?>[?turn],
      'items': items,
    }),
  ),
).entries.whereType<AgentChatTurnEntry>().single.section;

const AgentChatTimelineActions _actions = AgentChatTimelineActions(
  chatId: 'chat-1',
  onRetrySend: _ignore,
  onEditSend: _ignore,
  onOpenLink: _ignore,
  onOpenFile: _ignore,
  onImplementPlan: _noop,
);

void _ignore(String _) {}

void _noop() {}

Future<void> _pump(
  WidgetTester tester,
  AgentChatTurnSection section, {
  AgentChatExpansion? expansion,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10, 0, 7),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentChatTurnView(
              section: section,
              actions: _actions,
              expansion: expansion ?? AgentChatExpansion(),
              workspacePath: '/work',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a 50-action running turn shows one live row', (tester) async {
    final section = _section(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Do it all'),
      for (var index = 0; index < 49; index += 1) _command('c$index'),
      _command('c49', status: 'inProgress'),
    ], running: true);
    await _pump(tester, section);
    expect(find.text('Working for 7s'), findsOneWidget);
    expect(find.text('Running step c49'), findsOneWidget);
    expect(find.text('Ran step c0'), findsNothing);
    expect(find.text('49 earlier actions'), findsOneWidget);

    await tester.tap(find.text('49 earlier actions'));
    await tester.pump();
    expect(find.text('Running step c49'), findsNothing);
    expect(find.text('Ran 50 commands'), findsOneWidget);
  });

  testWidgets('a failed last action reads Thinking while the turn runs', (
    tester,
  ) async {
    final section = _section(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Go'),
      _command('c1'),
      _command('c2', status: 'failed'),
    ], running: true);
    await _pump(tester, section);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('2 earlier actions'), findsOneWidget);
  });

  for (final (status, label) in <(String, String)>[
    ('failed', 'Failed after 3s'),
    ('interrupted', 'Stopped after 3s'),
    ('cancelled', 'Cancelled after 3s'),
  ]) {
    testWidgets('a $status turn keeps its work unfolded', (tester) async {
      final section = _section(
        <Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Go'),
          _command('c1'),
          _command('c2', status: 'failed'),
        ],
        turn: <String, Object?>{
          'turnId': 'turn-1',
          'status': status,
          'startedAt': '2026-10-12T10:00:00Z',
          'completedAt': '2026-10-12T10:00:03Z',
        },
      );
      await _pump(tester, section);
      expect(find.text(label), findsOneWidget);
      // The grouped actions are visible without opening anything.
      expect(find.textContaining('Ran 2 commands'), findsOneWidget);
    });
  }

  testWidgets('a succeeded turn folds and lists its changed files', (
    tester,
  ) async {
    final section = _section(
      <Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Edit'),
        _command('c1'),
        _item(
          'f1',
          'file_change',
          normalized: <String, Object?>{
            'changes': <Object?>[
              <String, Object?>{
                'path': '/work/lib/a.dart',
                'kind': 'update',
                'diff': '+a',
              },
            ],
          },
        ),
        _item('a1', 'assistant_message', text: 'Done.'),
      ],
      turn: <String, Object?>{
        'turnId': 'turn-1',
        'status': 'completed',
        'startedAt': '2026-10-12T10:00:00Z',
        'completedAt': '2026-10-12T10:00:05Z',
      },
    );
    await _pump(tester, section);
    expect(find.text('Worked for 5s'), findsOneWidget);
    expect(find.textContaining('Edited 1 file'), findsNothing);
    expect(find.text('Changed Files (1)'), findsOneWidget);
    await tester.tap(find.text('Changed Files (1)'));
    await tester.pump();
    expect(find.text('lib/a.dart'), findsOneWidget);
  });

  testWidgets('folds survive a rebuild through the shared expansion', (
    tester,
  ) async {
    final expansion = AgentChatExpansion();
    final section = _section(
      <Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Go'),
        _command('c1'),
        _command('c2'),
        _item('a1', 'assistant_message', text: 'Done.'),
      ],
      turn: <String, Object?>{
        'turnId': 'turn-1',
        'status': 'completed',
        'startedAt': '2026-10-12T10:00:00Z',
        'completedAt': '2026-10-12T10:00:02Z',
      },
    );
    await _pump(tester, section, expansion: expansion);
    await tester.tap(find.text('Worked for 2s'));
    await tester.pump();
    expect(find.textContaining('Ran 2 commands'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, section, expansion: expansion);
    expect(find.textContaining('Ran 2 commands'), findsOneWidget);
  });

  testWidgets('the work header reports its expanded state', (tester) async {
    final handle = tester.ensureSemantics();
    final section = _section(
      <Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Go'),
        _command('c1'),
        _command('c2'),
      ],
      turn: <String, Object?>{
        'turnId': 'turn-1',
        'status': 'completed',
        'startedAt': '2026-10-12T10:00:00Z',
        'completedAt': '2026-10-12T10:00:02Z',
      },
    );
    await _pump(tester, section);
    final header = find.byKey(
      const ValueKey<String>('agent-chat-worked-turn-1'),
    );
    expect(
      tester.getSemantics(header),
      isSemantics(
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        label: 'Worked for 2s',
      ),
    );
    await tester.tap(header);
    await tester.pump();
    expect(
      tester.getSemantics(header),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );
    handle.dispose();
  });
}
