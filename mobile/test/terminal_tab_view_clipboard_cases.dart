part of 'terminal_tab_view_test.dart';

void _registerTerminalClipboardSecurityTests() {
  testWidgets('mobile emulators block OSC 52 writes and queries by default', (
    tester,
  ) async {
    final clipboardCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData' ||
            call.method == 'Clipboard.setData') {
          clipboardCalls.add(call.method);
        }
        if (call.method == 'Clipboard.getData') return {'text': 'private'};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = FakeTerminalClient()
      ..tabs = [fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    final payload = base64.encode(utf8.encode('unsolicited'));

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    view.focusNode!.requestFocus();
    await tester.pump();
    expect(view.focusNode!.hasFocus, isTrue);
    client.writes.clear();
    client.emitOutput(
      'session-tab-1',
      .fromList(utf8.encode('\x1b]52;c;?\x07\x1b]52;c;$payload\x07')),
    );
    await tester.pumpAndSettle();

    expect(clipboardCalls, isEmpty);
    expect(client.writes, isEmpty);
    expect(
      find.text(
        'Terminal clipboard write blocked. Enable OSC 52 clipboard writes in Settings.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'opted-in mobile emulators land OSC 52 writes on the phone and deny queries',
    (tester) async {
      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData' ||
              call.method == 'Clipboard.setData') {
            clipboardCalls.add(call);
          }
          if (call.method == 'Clipboard.getData') return {'text': 'private'};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final client = FakeTerminalClient()
        ..tabs = [fakeTab(id: 'tab-1', title: 'Terminal 1')];
      await _pumpTab(tester, client, allowOsc52Clipboard: true);
      final payload = base64.encode(utf8.encode('agent selection'));

      for (var generation = 0; generation < 2; generation++) {
        final view = tester.widget<TerminalView>(find.byType(TerminalView));
        view.focusNode!.requestFocus();
        await tester.pump();
        expect(view.focusNode!.hasFocus, isTrue);
        client.writes.clear();
        clipboardCalls.clear();
        client.emitOutput(
          'session-tab-1',
          .fromList(utf8.encode('\x1b]52;c;?\x07\x1b]52;c;$payload\x07')),
        );
        await tester.pumpAndSettle();
        // The query must not read the phone's clipboard nor answer the agent.
        expect(clipboardCalls.map((call) => call.method), <String>[
          'Clipboard.setData',
        ]);
        expect(
          (clipboardCalls.single.arguments as Map)['text'],
          'agent selection',
        );
        expect(client.writes, isEmpty);
        expect(find.text('Agent copied to clipboard'), findsOneWidget);

        if (generation == 0) {
          client.emitOutput(
            'session-tab-1',
            .fromList(utf8.encode('restored')),
            replacesScrollback: true,
          );
          await tester.pumpAndSettle();
          expect(_terminalOf(tester), isNot(same(view.terminal)));
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a local selection offers a Copy pill that fills the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = FakeTerminalClient()
      ..tabs = [fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    client.emitOutput(
      'session-tab-1',
      .fromList(utf8.encode('selectable words here')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);

    final controller = tester
        .widget<TerminalView>(find.byType(TerminalView))
        .controller!;
    final buffer = _terminalOf(tester).buffer;
    controller.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(10, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, 'selectable');
    expect(controller.selection, isNull);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
