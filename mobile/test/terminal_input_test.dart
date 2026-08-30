import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
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
            onKey: written.add,
            onAction: (_) async {},
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

  testWidgets('Paste is an ordinary key in the single scrolling row', (
    tester,
  ) async {
    final written = <List<int>>[];
    final actions = <TerminalAccessoryAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 320,
              child: TerminalAccessoryBar(
                keys: <TerminalAccessoryKey>[
                  builtInTerminalAccessoryKeysById['arrowUp']!,
                  builtInTerminalAccessoryKeysById['arrowDown']!,
                  builtInTerminalAccessoryKeysById['paste']!,
                ],
                onKey: written.add,
                onAction: (action) async => actions.add(action),
              ),
            ),
          ),
        ),
      ),
    );

    final arrowUp = find.byKey(
      const ValueKey<String>('terminal-accessory-arrowUp'),
    );
    final arrowDown = find.byKey(
      const ValueKey<String>('terminal-accessory-arrowDown'),
    );
    await tester.tap(arrowUp);
    await tester.tap(arrowDown);
    await tester.tap(
      find.byKey(const ValueKey<String>('terminal-accessory-paste')),
    );

    expect(actions, <TerminalAccessoryAction>[TerminalAccessoryAction.paste]);
    expect(written, <List<int>>[
      <int>[0x1b, 0x5b, 0x41],
      <int>[0x1b, 0x5b, 0x42],
    ]);
    // One row: no separate rail holds anything back.
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.getSize(arrowUp), const Size.square(48));
    expect(tester.getSize(arrowDown), const Size.square(48));
  });

  testWidgets('The key strip fades where more keys continue', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 320,
              child: TerminalAccessoryBar(
                keys: builtInTerminalAccessoryKeys,
                onKey: (_) {},
                onAction: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    const start = ValueKey<String>('terminal-accessory-fade-start');
    const end = ValueKey<String>('terminal-accessory-fade-end');
    expect(find.byKey(start), findsNothing);
    expect(find.byKey(end), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pump();

    expect(find.byKey(start), findsOneWidget);
  });

  testWidgets('The compose field and Send share one row', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: .min,
                  children: <Widget>[
                    TerminalAccessoryBar(
                      keys: const <TerminalAccessoryKey>[],
                      onKey: (_) {},
                      onAction: (_) async {},
                    ),
                    TerminalComposeBar(
                      hostId: 'host',
                      tabId: 'tab',
                      onSend: (text, {required bool withEnter}) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final send = tester.getRect(find.byTooltip('Send'));
    expect(send.size, const Size.square(48));

    // The field paints its own chrome at least a tap target tall and shares a
    // baseline with Send. The exact height is font dependent, and the test
    // fallback font is far taller than the bundled mono face, so asserting an
    // exact pixel height here would measure the test font, not the layout.
    final field = tester.getRect(
      find.byKey(const ValueKey<String>('terminal-compose-field')),
    );
    expect(field.height, greaterThanOrEqualTo(AleraTokens.minTapTarget));
    expect(field.bottom, send.bottom);
  });

  testWidgets('The first key and the compose field share the left inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: .min,
                  children: <Widget>[
                    TerminalAccessoryBar(
                      keys: <TerminalAccessoryKey>[
                        builtInTerminalAccessoryKeysById['arrowUp']!,
                      ],
                      onKey: (_) {},
                      onAction: (_) async {},
                    ),
                    TerminalComposeBar(
                      hostId: 'host',
                      tabId: 'tab',
                      onSend: (text, {required bool withEnter}) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final firstKey = tester.getRect(
      find.byKey(const ValueKey<String>('terminal-accessory-arrowUp')),
    );
    final field = tester.getRect(
      find.byKey(const ValueKey<String>('terminal-compose-field')),
    );
    expect(firstKey.left, field.left);
  });

  testWidgets(
    'Compose bar enables native correction and keeps Enter multiline',
    (tester) async {
      final sent = <(String, bool)>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAleraMobileDarkTheme(),
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
          theme: buildAleraMobileDarkTheme(),
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
