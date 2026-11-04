import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_approval_focus.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_pending_approval_row.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _approval(String id) =>
    AgentChatRequest.fromJson(<String, Object?>{
      'requestId': id,
      'kind': 'commandExecutionApproval',
      'createdAt': '2026-10-12T10:00:00Z',
      'command': 'make $id',
      'decisions': <Object?>['accept', 'decline'],
    });

const Key _composerKey = ValueKey<String>('composer');
const Key _elsewhereKey = ValueKey<String>('elsewhere');

final class _Harness {
  final TerminalComposerController composer = TerminalComposerController();
  final FocusNode elsewhere = FocusNode();
  final List<(String, AgentChatResponse)> responses =
      <(String, AgentChatResponse)>[];

  /// The typing guard reads this clock; [advance] moves it with fake time.
  DateTime now = DateTime.utc(2026, 10, 12, 10);

  late final ProviderContainer container = ProviderContainer(
    overrides: [agentChatClockProvider.overrideWithValue(() => now)],
  );

  Future<void> advance(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  Widget build(List<AgentChatRequest> approvals) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextField(key: _elsewhereKey, focusNode: elsewhere),
            AgentChatApprovalFocus(
              chatId: 'chat-1',
              approvals: approvals,
              composer: composer,
              child: Column(
                children: <Widget>[
                  for (final request in approvals)
                    AgentChatPendingApprovalRow(
                      request: request,
                      responding: false,
                      enabled: true,
                      onRespond: (response) =>
                          responses.add((request.id, response)),
                    ),
                ],
              ),
            ),
            TextField(
              key: _composerKey,
              controller: composer.textController,
              focusNode: composer.focusNode,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  late _Harness harness;
  setUp(() => harness = _Harness());
  tearDown(() {
    harness.composer.dispose();
    harness.elsewhere.dispose();
    harness.container.dispose();
  });

  testWidgets('a new approval row takes the keyboard from an idle composer', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();

    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);

    // The keyboard is on the row, not on a decision.
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    expect(harness.responses, isEmpty);

    // Tab reaches the first decision, which Enter then takes.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(harness.responses.single.$1, 'a1');
    expect(harness.responses.single.$2.toJson(), <String, Object?>{
      'type': 'approval',
      'decision': 'accept',
    });
  });

  testWidgets('Escape on an approval row returns to the composer', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isTrue);
    expect(harness.responses, isEmpty);
  });

  testWidgets('an approval arriving mid-sentence waits for a pause', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_composerKey));
    await tester.enterText(find.byKey(_composerKey), 'half a thou');
    await tester.pump();

    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isTrue);

    // Typing keeps the takeover held, and Enter stays in the composer.
    await harness.advance(tester, const Duration(milliseconds: 1000));
    await tester.enterText(find.byKey(_composerKey), 'half a thought');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await harness.advance(tester, const Duration(milliseconds: 1000));
    expect(harness.composer.focusNode.hasFocus, isTrue);
    expect(harness.responses, isEmpty);

    // A pause releases it; the draft stays.
    await harness.advance(tester, agentChatTypingIdle);
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);
    expect(harness.composer.textController.text, 'half a thought');
    expect(harness.responses, isEmpty);
  });

  testWidgets('an approval already seen does not take the keyboard again', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();

    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await harness.advance(tester, agentChatTypingIdle);
    expect(harness.composer.focusNode.hasFocus, isTrue);
  });

  testWidgets('an approval leaves a field elsewhere focused', (tester) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_elsewhereKey));
    await tester.pump();

    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await harness.advance(tester, agentChatTypingIdle);
    expect(harness.elsewhere.hasFocus, isTrue);
  });
}
