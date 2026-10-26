import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_timeline_sessions.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_view.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(
  String id,
  String type,
  String turnId,
  String text,
) => <String, Object?>{
  'itemId': id,
  'turnId': turnId,
  'type': type,
  'status': 'completed',
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'text': text,
};

AgentChatThread _thread(
  int turns, {
  List<Map<String, Object?>> requests = const <Map<String, Object?>>[],
}) => AgentChatThread.fromSnapshot(
  AgentChatSnapshot.fromJson(<String, Object?>{
    'chatId': 'chat-1',
    'workspaceId': 'ws-1',
    'cursor': 1,
    'session': <String, Object?>{'status': 'idle'},
    'items': <Object?>[
      for (var turn = 0; turn < turns; turn += 1) ...<Object?>[
        _item('u$turn', 'user_message', 'turn-$turn', 'Question $turn'),
        _item(
          'a$turn',
          'assistant_message',
          'turn-$turn',
          List<String>.filled(4, 'Answer line for turn $turn.').join('\n\n'),
        ),
      ],
    ],
    'pendingRequests': requests,
  }),
);

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

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(body: child),
      ),
    );

Widget _timeline(AgentChatTimelineProjection projection) =>
    AgentChatTimelineView(
      projection: projection,
      actions: _actions,
      workspacePath: '/work',
      canLoadEarlier: false,
      loadingEarlier: false,
      onLoadEarlier: _noop,
    );

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('agent-chat-timeline')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer(
      overrides: [
        chatTasksSupportedProvider.overrideWith((ref) async => false),
      ],
    );
  });
  tearDown(() => container.dispose());

  testWidgets('a new chat follows its output to the end', (tester) async {
    await tester.pumpWidget(
      _host(
        container,
        _timeline(AgentChatTimelineProjection.build(_thread(30))),
      ),
    );
    await tester.pumpAndSettle();
    expect(_position(tester).extentAfter, lessThan(1));
  });

  testWidgets('scrolling away frees the timeline and a remount restores it', (
    tester,
  ) async {
    final projection = AgentChatTimelineProjection.build(_thread(30));
    await tester.pumpWidget(_host(container, _timeline(projection)));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey<String>('agent-chat-timeline')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    final session = container
        .read(agentChatTimelineSessionsProvider)
        .of('chat-1');
    expect(session.mode, AgentChatScrollMode.free);
    final saved = _position(tester).pixels;
    expect(find.text('Scroll To End'), findsOneWidget);

    // New output does not move a reader who scrolled away.
    final grown = AgentChatTimelineProjection.build(
      _thread(31),
      previous: projection,
    );
    await tester.pumpWidget(_host(container, _timeline(grown)));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(saved, 1));

    // A tab switch unmounts the timeline; coming back restores the place.
    await tester.pumpWidget(_host(container, const SizedBox.shrink()));
    await tester.pumpWidget(_host(container, _timeline(grown)));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(saved, 1));

    await tester.tap(find.text('Scroll To End'));
    await tester.pumpAndSettle();
    expect(_position(tester).extentAfter, lessThan(1));
    expect(session.mode, AgentChatScrollMode.following);
  });

  testWidgets('the pill names a pending approval', (tester) async {
    await tester.pumpWidget(
      _host(
        container,
        _timeline(
          AgentChatTimelineProjection.build(
            _thread(
              30,
              requests: <Map<String, Object?>>[
                <String, Object?>{
                  'requestId': 'r1',
                  'kind': 'commandExecutionApproval',
                  'createdAt': '2026-10-12T10:00:00Z',
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('agent-chat-timeline')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(find.text('Approval Needed'), findsOneWidget);
  });

  testWidgets('streaming into the live turn reuses settled turn widgets', (
    tester,
  ) async {
    final thread = _thread(3);
    final before = AgentChatTimelineProjection.build(thread);
    await tester.pumpWidget(_host(container, _timeline(before)));
    await tester.pumpAndSettle();
    AgentChatTurnView turnView(String turnId) =>
        tester.widget<AgentChatTurnView>(
          find.descendant(
            of: find.byKey(ValueKey<String>('agent-chat-entry:turn-$turnId')),
            matching: find.byType(AgentChatTurnView),
          ),
        );
    final settled = turnView('turn-1');

    final outcome = thread.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'chat-1',
        'cursor': 2,
        'delta': <String, Object?>{
          'items': <Object?>[
            _item('a2', 'assistant_message', 'turn-2', 'Streaming more'),
          ],
        },
      }),
    );
    final after = AgentChatTimelineProjection.build(
      (outcome as AgentChatApplied).thread,
      previous: before,
    );
    await tester.pumpWidget(_host(container, _timeline(after)));
    await tester.pump();
    expect(identical(turnView('turn-1'), settled), isTrue);
  });

  testWidgets('a sent message anchors near the top of the timeline', (
    tester,
  ) async {
    final thread = _thread(30);
    final projection = AgentChatTimelineProjection.build(thread);
    await tester.pumpWidget(_host(container, _timeline(projection)));
    await tester.pumpAndSettle();

    final sent = AgentChatTimelineProjection.build(
      thread,
      outgoing: <AgentChatOutgoingMessage>[
        AgentChatOutgoingMessage(
          clientMessageId: 'm1',
          text: 'One more thing',
          createdAt: DateTime.utc(2026, 10, 12, 11),
        ),
      ],
      previous: projection,
    );
    await tester.pumpWidget(_host(container, _timeline(sent)));
    await tester.pumpAndSettle();
    final session = container
        .read(agentChatTimelineSessionsProvider)
        .of('chat-1');
    expect(session.mode, AgentChatScrollMode.anchoring);
    final scrollTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('agent-chat-timeline')))
        .dy;
    final messageTop = tester.getTopLeft(find.text('One more thing')).dy;
    // The prompt sits in the upper part of the viewport, not at the bottom.
    expect(messageTop - scrollTop, lessThan(120));
  });
}
