import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tool_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _note = 'Only part of this message is loaded.';
const _tail = '  final value = **unfinished**;\n```\n  ';

AgentChatItem _item({
  String id = 'tail',
  AgentChatItemType type = AgentChatItemType.assistantMessage,
  String text = _tail,
  String reasoning = '',
  String output = '',
  String? detail,
  AgentChatItemOrigin? origin,
  Map<String, Object?> normalized = const <String, Object?>{},
  bool partial = false,
}) => AgentChatItem(
  id: id,
  type: type,
  status: AgentChatItemStatus.completed,
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: DateTime.utc(2026, 10, 12),
  text: text,
  reasoningText: reasoning,
  output: output,
  detail: detail,
  origin: origin,
  normalized: normalized,
  isPartialContinuation: partial,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: .topLeft,
          child: SizedBox(width: 360, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Widget _message(AgentChatItem item) =>
    item.type == AgentChatItemType.userMessage
    ? AgentChatUserMessage(item: item)
    : AgentChatAssistantMessage(item: item);

AgentChatItem _project(AgentChatThread thread) =>
    (AgentChatTimelineProjection.build(thread).entries.single
            as AgentChatStandaloneEntry)
        .item;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final copied = <String>[];
  setUp(() {
    copied.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  for (final type in <AgentChatItemType>[
    AgentChatItemType.userMessage,
    AgentChatItemType.assistantMessage,
  ]) {
    testWidgets('partial $type preserves literal text and copy', (
      tester,
    ) async {
      await _pump(tester, _message(_item(type: type, partial: true)));
      expect(find.text(_note), findsOneWidget);
      expect(find.byType(AgentChatMarkdown), findsNothing);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        _tail,
      );

      await tester.tap(find.byTooltip('Copy Message'));
      await tester.pump();
      expect(copied, <String>[_tail]);
    });
  }

  testWidgets('loading the head restores joined Markdown', (tester) async {
    final tail = _item(
      normalized: <String, Object?>{
        'continuationOf': 'head',
        'segmentIndex': 1,
        'stream': 'text',
      },
    );
    final thread = AgentChatThread.fromSnapshot(
      AgentChatSnapshot(
        chatId: 'chat',
        workspaceId: 'workspace',
        cursor: 1,
        items: <AgentChatItem>[tail],
      ),
    );
    await _pump(tester, _message(_project(thread)));
    expect(find.text(_note), findsOneWidget);
    expect(find.byType(AgentChatMarkdown), findsNothing);

    const prefix = '```dart\n';
    final complete = thread.prependHistory(
      AgentChatHistoryPage(
        items: <AgentChatItem>[_item(id: 'head', text: prefix)],
      ),
    );
    await _pump(tester, _message(_project(complete)));
    expect(find.text(_note), findsNothing);
    expect(
      tester.widget<AgentChatMarkdown>(find.byType(AgentChatMarkdown)).text,
      '$prefix$_tail',
    );
  });

  testWidgets('partial reasoning stays literal when expanded', (tester) async {
    await _pump(
      tester,
      AgentChatItemRowView(
        item: _item(
          type: AgentChatItemType.reasoning,
          text: '',
          reasoning: _tail,
          partial: true,
        ),
      ),
    );
    await tester.tap(find.text('Thought'));
    await tester.pump();
    expect(find.text(_note), findsOneWidget);
    expect(find.byType(AgentChatMarkdown), findsNothing);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      _tail,
    );
  });

  testWidgets('partial automated input stays a notice', (tester) async {
    final item = _item(
      type: AgentChatItemType.userMessage,
      partial: true,
      origin: const AgentChatItemOrigin(
        kind: AgentChatItemOriginKind.chatMessage,
      ),
    );
    await _pump(tester, _message(item));
    expect(find.text('Message from another chat'), findsOneWidget);
    expect(find.text(_note), findsOneWidget);
    expect(find.byTooltip('Copy Message'), findsNothing);
    await tester.tap(find.text('Message from another chat'));
    await tester.pump();
    expect(find.text(_note), findsOneWidget);
    expect(find.byType(AgentChatMarkdown), findsNothing);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      _tail,
    );
  });

  testWidgets('partial tool output has one note and keeps canonical details', (
    tester,
  ) async {
    await _pump(
      tester,
      AgentChatToolDetails(
        item: _item(
          type: AgentChatItemType.dynamicToolCall,
          text: '',
          output: _tail,
          detail: 'Canonical tool details.',
          partial: true,
        ),
      ),
    );
    expect(find.text(_note), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      _tail,
    );
    expect(
      find.text('Canonical tool details.', findRichText: true),
      findsOneWidget,
    );
  });
}
