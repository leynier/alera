part of 'terminal_runtime_native_test.dart';

void _registerTerminalRuntimeOutputBackpressureTests() {
  test('bounds pending terminal output during a burst', () {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    queueTerminalOutputForTesting(session, 'a' * (1024 * 1024 + 64 * 1024));

    expect(
      pendingTerminalOutputCharsForTesting(session),
      lessThanOrEqualTo(1024 * 1024),
    );
  });
}
