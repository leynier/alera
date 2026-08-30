part of 'terminal_tab_view_test.dart';

void _registerTerminalClipboardSecurityTests() {
  testWidgets('focused mobile emulators deny remote clipboard access', (
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

    for (var generation = 0; generation < 2; generation++) {
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      view.focusNode!.requestFocus();
      await tester.pump();
      expect(view.focusNode!.hasFocus, isTrue);
      client.writes.clear();
      client.emitOutput(
        'session-tab-1',
        Uint8List.fromList(
          utf8.encode('\x1b]52;c;?\x07\x1b]52;c;$payload\x07'),
        ),
      );
      await tester.pumpAndSettle();
      expect(clipboardCalls, isEmpty);
      expect(client.writes, isEmpty);

      if (generation == 0) {
        client.emitOutput(
          'session-tab-1',
          Uint8List.fromList(utf8.encode('restored')),
          replacesScrollback: true,
        );
        await tester.pumpAndSettle();
        expect(_terminalOf(tester), isNot(same(view.terminal)));
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
