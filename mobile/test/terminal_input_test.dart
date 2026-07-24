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

  testWidgets('Compose bar sends text with Enter and clears the field', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalComposeBar(
            onSend: (text, {required bool withEnter}) {
              sent.add(withEnter ? '$text\\r' : text);
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'ls -la');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(sent, <String>['ls -la\\r']);
    expect(find.text('ls -la'), findsNothing);

    // An empty send still presses Enter.
    await tester.tap(find.byTooltip('Send'));
    expect(sent, <String>['ls -la\\r', '\\r']);
  });
}
