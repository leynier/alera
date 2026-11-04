import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_chat_actions.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_task_transport.dart';
import 'support/phone_modal_harness.dart';

const ValueKey<String> _submit = ValueKey<String>('sendToChatSubmit');

/// Opens Send To Chat from `chat-1` on a phone of [size].
Future<FakeChatTaskTransport> _openSheet(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboard = 0,
  double homeIndicator = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = FakeViewPadding(top: 47, bottom: homeIndicator);
  tester.view.viewPadding = FakeViewPadding(top: 47, bottom: homeIndicator);
  addTearDown(tester.view.reset);
  final transport = FakeChatTaskTransport()
    ..chats = <Map<String, Object?>>[
      <String, Object?>{'chatId': 'chat-1', 'title': 'Parent chat'},
      <String, Object?>{
        'chatId': 'chat-2',
        'title': 'Review chat',
        'workspaceName': 'feature-oauth',
      },
    ];
  addTearDown(transport.dispose);
  var ids = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileChatTaskRepositoryProvider('host').overrideWith(
          (ref) async => RuntimeAgentChatOrchestrationRepository(transport),
        ),
        agentChatRepositoryProvider('host')
            .overrideWith((ref) async => RuntimeAgentChatRepository(transport)),
        mobileChatTaskPlacesProvider('host')
            .overrideWith((ref) async => const MobileChatTaskPlaces()),
        mobileChatTaskIdGeneratorProvider.overrideWithValue(
          () => 'id-${ids++}',
        ),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSendToChatSheet(
                context,
                hostId: 'host',
                fromChatId: 'chat-1',
                workspaceId: 'ws-1',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return transport;
}

double _visibleBottom(WidgetTester tester) =>
    tester.view.physicalSize.height - tester.view.viewInsets.bottom;

void main() {
  setUpAll(loadShippedInter);
  testWidgets('Send clears the home indicator', (tester) async {
    await _openSheet(tester, homeIndicator: 34);

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(_submit)).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 34),
    );
  });

  testWidgets('a short phone at 200% text sends and offers View Task', (
    tester,
  ) async {
    final transport = await _openSheet(
      tester,
      size: const Size(320, 568),
      textScale: 2,
      keyboard: 260,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('sendToChatTarget')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review chat · feature-oauth').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sendToChatMessage')),
        matching: find.byType(TextField),
      ),
      'Check the parser',
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(_submit),
      48,
      scrollable: find
          .ancestor(of: find.byKey(_submit), matching: find.byType(Scrollable))
          .first,
    );
    expect(
      tester.getRect(find.byKey(_submit)).bottom,
      lessThanOrEqualTo(_visibleBottom(tester)),
    );
    await tester.tap(find.byKey(_submit));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final sent = transport.sent(AgentChatOrchestrationWire.send).single;
    expect(sent['chatId'], 'chat-2');
    expect(sent['message'], 'Check the parser');
    expect(sent['expectReply'], isTrue);
    expect(find.byKey(_submit), findsNothing);
    expect(find.text('Message sent.'), findsOneWidget);

    // The action stays until it is used, and only it opens the task.
    final viewTask = find.text('View Task');
    await tester.pump(const Duration(seconds: 10));
    expect(viewTask, findsOneWidget);
    expect(find.byType(ChatTaskDetailScreen), findsNothing);
    expect(tester.getRect(viewTask).right, lessThanOrEqualTo(320));
    await tester.tap(viewTask);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ChatTaskDetailScreen), findsOneWidget);
    expect(find.text('Message sent.'), findsNothing);
  });

  testWidgets('without Expect A Reply the SnackBar has no View Task', (
    tester,
  ) async {
    final transport = await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey<String>('sendToChatTarget')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review chat · feature-oauth').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sendToChatMessage')),
        matching: find.byType(TextField),
      ),
      'FYI',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('sendToChatExpectReply')),
    );
    await tester.tap(find.byKey(_submit));
    await tester.pumpAndSettle();

    final sent = transport.sent(AgentChatOrchestrationWire.send).single;
    expect(sent['expectReply'], isFalse);
    expect(find.text('Message sent.'), findsOneWidget);
    expect(find.text('View Task'), findsNothing);
  });
}
