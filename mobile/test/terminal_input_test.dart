import 'package:alera_mobile/src/features/terminal/application/terminal_input_mode_controller.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Compose is the default mode and the direct opt-in sticks per tab', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(terminalInputModeControllerProvider('tab-1')),
      TerminalInputMode.compose,
    );

    container
        .read(terminalInputModeControllerProvider('tab-1').notifier)
        .toggle();
    expect(
      container.read(terminalInputModeControllerProvider('tab-1')),
      TerminalInputMode.direct,
    );
    // Another tab keeps its own compose default.
    expect(
      container.read(terminalInputModeControllerProvider('tab-2')),
      TerminalInputMode.compose,
    );
  });

  testWidgets('Accessory bar writes the exact key bytes', (tester) async {
    final written = <List<int>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalAccessoryBar(
            keys: <TerminalAccessoryKey>[
              builtInTerminalAccessoryKeysById['escape']!,
              builtInTerminalAccessoryKeysById['shiftTab']!,
              builtInTerminalAccessoryKeysById['ctrlC']!,
            ],
            inputMode: TerminalInputMode.compose,
            onKey: written.add,
            onPaste: () async {},
            onToggleMode: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Esc'));
    await tester.tap(find.text('Shift+Tab'));
    await tester.tap(find.text('Ctrl+C'));

    expect(written, <List<int>>[
      <int>[0x1b],
      <int>[0x1b, 0x5b, 0x5a],
      <int>[0x03],
    ]);
  });

  testWidgets('Paste and vertical arrows stay in the pinned command rail', (
    tester,
  ) async {
    final written = <List<int>>[];
    var pasteCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 320,
              child: TerminalAccessoryBar(
                keys: builtInTerminalAccessoryKeys,
                inputMode: TerminalInputMode.compose,
                onKey: written.add,
                onPaste: () async {
                  pasteCount += 1;
                },
                onToggleMode: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Paste Clipboard'));
    final arrowUp = find.byKey(
      const ValueKey<String>('terminal-accessory-arrowUp'),
    );
    final arrowDown = find.byKey(
      const ValueKey<String>('terminal-accessory-arrowDown'),
    );
    await tester.tap(arrowUp);
    await tester.tap(arrowDown);

    expect(pasteCount, 1);
    expect(written, <List<int>>[
      <int>[0x1b, 0x5b, 0x41],
      <int>[0x1b, 0x5b, 0x42],
    ]);
    expect(tester.getSize(arrowUp), const Size.square(48));
    expect(tester.getSize(arrowDown), const Size.square(48));
  });

  testWidgets(
    'Compose bar enables native correction and keeps Enter multiline',
    (tester) async {
      final sent = <(String, bool)>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TerminalComposeBar(
                hostId: 'host',
                tabId: 'tab',
                onSend: (text, {required bool withEnter}) {
                  sent.add((text, withEnter));
                },
              ),
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isTrue);
      expect(field.enableSuggestions, isTrue);
      expect(field.textInputAction, TextInputAction.newline);

      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pump();

      expect(field.controller!.text, 'first\nsecond');
      expect(sent, isEmpty);
    },
  );

  testWidgets('Compose bar sends text with Enter and clears the field', (
    tester,
  ) async {
    // The bar hands over the text and the intent; how they reach the PTY is
    // TerminalComposeDelivery's decision, not this widget's.
    final sent = <(String, bool)>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TerminalComposeBar(
              hostId: 'host',
              tabId: 'tab',
              onSend: (text, {required bool withEnter}) {
                sent.add((text, withEnter));
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'ls -la');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(sent, <(String, bool)>[('ls -la', true)]);
    expect(find.text('ls -la'), findsNothing);

    // An empty send still presses Enter.
    await tester.tap(find.byTooltip('Send'));
    expect(sent, <(String, bool)>[('ls -la', true), ('', true)]);
  });
}
