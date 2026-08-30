part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceClipboardTests() {
  testWidgets('focused terminal denies clipboard reads and gates writes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
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
      final factory = _FakeTerminalPtySessionFactory();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: _testShellLaunches,
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      await _pumpTerminalSurface(tester, session);
      final view = tester.widget<xterm.TerminalView>(
        find.byType(xterm.TerminalView),
      );
      view.focusNode!.requestFocus();
      await tester.pump();
      expect(view.focusNode!.hasFocus, isTrue);
      final pty = factory.sessions.single;
      pty.writes.clear();
      final payload = base64.encode(utf8.encode('allowed write'));

      pty.emitOutput(utf8.encode('\x1b]52;c;?\x07\x1b]52;c;$payload\x07'));
      await _pumpTerminalOutput(tester);
      expect(clipboardCalls, isEmpty);
      expect(pty.writes, isEmpty);

      runtime.updateSettings(
        TerminalSettings.defaults.copyWith(allowOsc52Clipboard: true),
      );
      pty.emitOutput(utf8.encode('\x1b]52;c;?\x07\x1b]52;c;$payload\x07'));
      await _pumpTerminalOutput(tester);
      expect(clipboardCalls.map((call) => call.method), ['Clipboard.setData']);
      expect(clipboardCalls.single.arguments, {'text': 'allowed write'});
      expect(pty.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
