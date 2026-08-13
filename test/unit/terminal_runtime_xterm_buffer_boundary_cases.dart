part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeBufferBoundaryTests() {
  test(
    'batches printable output after a resized cursor restore at capacity',
    () {
      final session = _sessionWithCursorRestoredAtBufferCapacity();

      queueTerminalOutputForTesting(session, 'x');

      expect(() => flushTerminalOutputForTesting(session), returnsNormally);
      expect(terminalBufferTextForTesting(session), endsWith('x'));
    },
  );

  test('batches line erase after a resized cursor restore at capacity', () {
    final session = _sessionWithCursorRestoredAtBufferCapacity(
      lastLineText: 'stale',
    );

    queueTerminalOutputForTesting(session, '\x1b[K');

    expect(() => flushTerminalOutputForTesting(session), returnsNormally);
    expect(terminalBufferTextForTesting(session), endsWith('\n'));
  });
}

TerminalSessionHandle _sessionWithCursorRestoredAtBufferCapacity({
  String lastLineText = '',
}) {
  final runtime = XtermTerminalRuntime(
    ptySessionFactory: _FakeTerminalPtySessionFactory(),
    initialSettings: TerminalSettings.defaults.copyWith(scrollbackLines: 5000),
    shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
      _launch('shell', shell: '/bin/sh'),
    ],
  );
  addTearDown(runtime.dispose);
  final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

  resizeTerminalForTesting(session, 8, 5);
  queueTerminalOutputForTesting(session, '\x1b[5;1H\x1b7');
  flushTerminalOutputForTesting(session);
  resizeTerminalForTesting(session, 8, 3);
  queueTerminalOutputForTesting(session, '\r\n' * 5000);
  flushTerminalOutputForTesting(session);
  queueTerminalOutputForTesting(session, '$lastLineText\x1b8');
  flushTerminalOutputForTesting(session);

  expect(terminalBufferTextForTesting(session).split('\n'), hasLength(5000));
  return session;
}
