import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_queued_edit.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const AgentChatComposerSettings _settings = AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: AgentChatSession(status: AgentChatSessionStatus.ready),
  providers: <AgentChatProviderInstance>[],
  canSwitchProvider: true,
  configuring: false,
  catalog: AgentChatCatalogState.loading,
);

final AgentChatQueueEntry _queued = AgentChatQueueEntry(
  queueId: 'q1',
  clientMessageId: 'm1',
  text: 'Queued text',
  createdAt: DateTime.utc(2026, 10, 25),
);

void main() {
  late TerminalComposerController composer;
  late AgentChatQueuedEdit edit;
  late List<String> sent;
  late List<(String, String)> saved;
  late int interrupts;

  Future<void> pump(WidgetTester tester) async {
    composer = TerminalComposerController();
    edit = AgentChatQueuedEdit(composer);
    addTearDown(edit.dispose);
    addTearDown(composer.dispose);
    sent = <String>[];
    saved = <(String, String)>[];
    interrupts = 0;
    composer.textController.text = 'My draft';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AgentChatComposer(
              controller: composer,
              workspaceId: 'ws-1',
              chatId: 'chat-1',
              settings: _settings,
              usage: const AgentChatUsage(),
              canSend: true,
              busy: true,
              canInterrupt: true,
              interrupting: false,
              hintText: 'Message the agent',
              promptHistory: () => const <String>[],
              onSend: (text, _, {steer = false}) {
                sent.add(text);
                return true;
              },
              onInterrupt: () => interrupts += 1,
              onConfigure: (_) {},
              onChoose: (_, _) {},
              onOpenFile: (_) {},
              queuedEdit: edit,
              onSaveQueuedEdit: (queueId, text) async {
                saved.add((queueId, text));
                return null;
              },
            ),
          ),
        ),
      ),
    );
    edit.begin(_queued);
    await tester.pump();
  }

  const banner = ValueKey<String>('agent-chat-queued-edit-banner');

  testWidgets('Enter saves the edit in place instead of sending', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(banner), findsOneWidget);
    expect(find.text('Editing Queued Message'), findsOneWidget);
    expect(composer.textController.text, 'Queued text');

    await tester.enterText(find.byType(TextField), 'Edited text');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(saved, <(String, String)>[('q1', 'Edited text')]);
    expect(sent, isEmpty);
    expect(find.byKey(banner), findsNothing);
    expect(composer.textController.text, 'My draft');
  });

  testWidgets('Escape cancels the edit before it would stop the turn', (
    tester,
  ) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(banner), findsNothing);
    expect(composer.textController.text, 'My draft');
    expect(interrupts, 0);
    expect(saved, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(interrupts, 1);
  });

  testWidgets('the banner Cancel restores the draft', (tester) async {
    await pump(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-banner-cancel')),
    );
    await tester.pump();
    await tester.pump();
    expect(edit.isEditing, isFalse);
    expect(composer.textController.text, 'My draft');
  });
}
