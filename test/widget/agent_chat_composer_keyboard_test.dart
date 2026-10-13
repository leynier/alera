import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Harness {
  _Harness(this.history);

  final List<String> history;
  final TerminalComposerController composer = TerminalComposerController();
  final List<String> sent = <String>[];
  int interrupts = 0;

  TextEditingController get text => composer.textController;

  Widget build({bool canInterrupt = false}) => MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: AgentChatComposer(
          controller: composer,
          workspaceId: 'ws-1',
          chatId: 'chat-1',
          settings: null,
          usage: const AgentChatUsage(),
          canSend: true,
          busy: canInterrupt,
          canInterrupt: canInterrupt,
          interrupting: false,
          hintText: 'Message the agent',
          promptHistory: () => history,
          onSend: (text, _) {
            sent.add(text);
            return true;
          },
          onInterrupt: () => interrupts += 1,
          onConfigure: (_) {},
          onOpenFile: (_) {},
        ),
      ),
    ),
  );
}

Future<_Harness> _pump(
  WidgetTester tester,
  List<String> history, {
  bool canInterrupt = false,
}) async {
  final harness = _Harness(history);
  addTearDown(harness.composer.dispose);
  await tester.pumpWidget(harness.build(canInterrupt: canInterrupt));
  await tester.tap(find.byType(TextField));
  await tester.pump();
  return harness;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('Up and Down walk the history from an empty box', (tester) async {
    final harness = await _pump(tester, <String>['first', 'second']);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'second');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'first');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(harness.text.text, 'second');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(harness.text.text, isEmpty);
  });

  testWidgets('editing a recalled prompt keeps Up and Down from replacing it', (
    tester,
  ) async {
    final harness = await _pump(tester, <String>['first', 'second']);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'second');
    await tester.enterText(find.byType(TextField), 'second, edited');
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'second, edited');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(harness.text.text, 'second, edited');
  });

  testWidgets('Up moves through a recalled multiline prompt before recalling', (
    tester,
  ) async {
    final harness = await _pump(tester, <String>[
      'older',
      'line one\nline two',
    ]);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'line one\nline two');

    // The caret sits on the last line, so Up is a caret move.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'line one\nline two');
    expect(
      harness.text.selection.extentOffset,
      lessThan('line one'.length + 1),
    );

    // From the first line, Up goes on to the earlier prompt.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'older');
  });

  testWidgets('Down moves through a multiline prompt before the next one', (
    tester,
  ) async {
    final harness = await _pump(tester, <String>['a\nb', 'newest']);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'a\nb');
    harness.text.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(harness.text.text, 'a\nb');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(harness.text.text, 'newest');
  });

  testWidgets('modified arrows edit the text instead of recalling history', (
    tester,
  ) async {
    final harness = await _pump(tester, <String>['first', 'second']);

    for (final modifier in <LogicalKeyboardKey>[
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await _press(tester, LogicalKeyboardKey.arrowUp, modifier: modifier);
      expect(harness.text.text, isEmpty, reason: '$modifier+Up');
    }

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, 'second');
    for (final modifier in <LogicalKeyboardKey>[
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await _press(tester, LogicalKeyboardKey.arrowUp, modifier: modifier);
      expect(harness.text.text, 'second', reason: '$modifier+Up');
      await _press(tester, LogicalKeyboardKey.arrowDown, modifier: modifier);
      expect(harness.text.text, 'second', reason: '$modifier+Down');
    }
  });

  testWidgets(
    'keys an input method is composing with stay with the input method',
    (tester) async {
      final harness = await _pump(tester, <String>[
        'first',
      ], canInterrupt: true);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(harness.text.text, 'first');
      const composing = TextEditingValue(
        text: 'firstにほ',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      );
      harness.text.value = composing;
      await tester.pump();

      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
      ]) {
        expect(await tester.sendKeyEvent(key), isFalse, reason: '$key');
      }
      await tester.pump();

      expect(harness.text.value, composing);
      expect(harness.sent, isEmpty);
      expect(harness.interrupts, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
