import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatItem _message(
  String id,
  String text, {
  List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
}) => AgentChatItem(
  id: id,
  type: AgentChatItemType.userMessage,
  status: AgentChatItemStatus.completed,
  createdAt: DateTime.utc(2026, 10, 26),
  updatedAt: DateTime.utc(2026, 10, 26),
  text: text,
  attachments: attachments,
);

Future<void> _pump(WidgetTester tester, List<Widget> children) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(child: Column(children: children)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('media sits above the bubble and files become cards', (
    tester,
  ) async {
    await _pump(tester, <Widget>[
      AgentChatUserMessage(
        item: _message(
          'u1',
          'Look at these',
          attachments: const <AgentChatAttachment>[
            AgentChatAttachment(type: .image, path: '/host/a.png'),
            AgentChatAttachment(type: .file, path: '/host/clip.mp4'),
            AgentChatAttachment(
              type: .file,
              path: '/host/report.pdf',
              sizeBytes: 1258291,
            ),
            AgentChatAttachment(
              type: .file,
              name: 'Pasted File',
              mimeType: 'text/plain',
              sizeBytes: 2048,
            ),
          ],
        ),
      ),
    ]);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-media-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-media-1')),
      findsOneWidget,
    );
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('PDF · 1.2 MB'), findsOneWidget);
    expect(find.text('Pasted text'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(
      tester
          .getBottomLeft(
            find.byKey(const ValueKey<String>('agent-chat-media-0')),
          )
          .dy,
      lessThan(tester.getTopLeft(find.text('Look at these')).dy),
    );
  });

  testWidgets('back-to-back steers share one label', (tester) async {
    final steers = <AgentChatItem>[
      _message('s1', 'Also run the tests'),
      _message('s2', 'And the linter'),
    ];
    final placements = agentChatSteerPlacements(steers);
    await _pump(tester, <Widget>[
      for (final (index, steer) in steers.indexed)
        AgentChatUserMessage(item: steer, steer: placements[index]),
    ]);
    expect(find.text(agentChatSteerLabel), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(agentChatSteerLabel)).dy,
      greaterThan(tester.getBottomLeft(find.text('And the linter')).dy),
    );
  });
}
