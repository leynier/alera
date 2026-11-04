import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatItem _wake(List<String> taskIds) => AgentChatItem(
  id: 'wake',
  type: AgentChatItemType.userMessage,
  status: AgentChatItemStatus.completed,
  createdAt: DateTime.utc(2026, 10, 26),
  updatedAt: DateTime.utc(2026, 10, 26),
  text: 'Subagent completed: Count the files\n\nResult:\n42 files',
  origin: AgentChatItemOrigin(
    kind: AgentChatItemOriginKind.subagentWake,
    taskIds: taskIds,
  ),
);

Future<void> _pump(WidgetTester tester, AgentChatItem item) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      home: Scaffold(body: AgentChatUserMessage(item: item)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a sub-agent wake reads as a notice, not as the person', (
    tester,
  ) async {
    await _pump(tester, _wake(const <String>['child']));
    expect(find.text('A sub-agent finished'), findsOneWidget);
    expect(find.byTooltip('Copy Message'), findsNothing);
    expect(find.textContaining('42 files', findRichText: true), findsNothing);
    await tester.tap(find.text('A sub-agent finished'));
    await tester.pump();
    expect(find.textContaining('42 files', findRichText: true), findsOneWidget);
  });

  testWidgets('a wake for several sub-agents counts them', (tester) async {
    await _pump(tester, _wake(const <String>['a', 'b']));
    expect(find.text('2 sub-agents finished'), findsOneWidget);
  });
}
