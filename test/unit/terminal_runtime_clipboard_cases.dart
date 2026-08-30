part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeClipboardTests() {
  for (final size in [7000, 98304]) {
    test('gated OSC 52 copies $size bytes through the escape parser', () async {
      final clipboard = _FakeTerminalClipboard();
      final runtime = XtermTerminalRuntime(
        terminalClipboard: clipboard,
        ptySessionFactory: _FakeTerminalPtySessionFactory(),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      runtime.updateSettings(
        TerminalSettings.defaults.copyWith(allowOsc52Clipboard: true),
      );
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      final text = 'a' * size;
      final payload = base64.encode(utf8.encode(text));
      handlePrivateOscForTesting(session, '52', ['c', payload]);
      await Future<void>.delayed(.zero);
      expect(clipboard.writes, [text]);
    });
  }

  test('handles gated OSC 52 clipboard writes once per runtime', () async {
    final clipboard = _FakeTerminalClipboard();
    final notices = <String>[];
    final runtime = XtermTerminalRuntime(
      terminalClipboard: clipboard,
      interactionNotice: (message, {error = false}) => notices.add(message),
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    final payload = base64.encode(utf8.encode('from tui'));
    handlePrivateOscForTesting(session, '52', <String>['c', payload]);
    handlePrivateOscForTesting(session, '52', <String>['c', payload]);
    await Future<void>.delayed(.zero);

    expect(clipboard.writes, isEmpty);
    expect(notices, hasLength(1));

    runtime.updateSettings(
      TerminalSettings.defaults.copyWith(allowOsc52Clipboard: true),
    );
    handlePrivateOscForTesting(session, '52', <String>['c', payload]);
    await Future<void>.delayed(.zero);

    expect(clipboard.writes, <String>['from tui']);
    handlePrivateOscForTesting(session, '52', ['', payload]);
    handlePrivateOscForTesting(session, '52', ['c', '?']);
    handlePrivateOscForTesting(session, '52', ['c', payload, 'trailing']);
    handlePrivateOscForTesting(session, '5522', ['type=write', payload]);
    handlePrivateOscForTesting(session, '52', ['c', '====']);
    handlePrivateOscForTesting(session, '52', ['c', 'A' * (128 * 1024 + 4)]);
    writeTerminalOutputForTesting(
      session,
      '\x1b]1337;CopyToClipboard=c\x07secret\x1b]1337;EndCopy\x07',
    );
    await Future<void>.delayed(.zero);
    expect(clipboard.writes, <String>['from tui']);
  });

  test('pastes clipboard text before probing for an image', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fakeSession = _FakeTerminalPtySession();
    final clipboard = _FakeTerminalClipboard(
      text: 'clipboard text',
      imagePath: '/tmp/alera-paste.png',
    );
    final runtime = XtermTerminalRuntime(
      terminalClipboard: clipboard,
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    await session.ensureStarted();
    expect(session.isRunning, isTrue);
    feedTerminalInputForTesting(session, 'probe');
    expect(utf8.decode(fakeSession.writes.single), 'probe');
    fakeSession.writes.clear();

    await pasteTerminalClipboardForTesting(session);

    expect(utf8.decode(fakeSession.writes.single), 'clipboard text');
    expect(clipboard.imageReadCount, 0);
  });

  test('pastes a temporary image path for image-only clipboards', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fakeSession = _FakeTerminalPtySession();
    final clipboard = _FakeTerminalClipboard(
      text: '',
      imagePath: '/tmp/alera-paste.png',
    );
    final runtime = XtermTerminalRuntime(
      terminalClipboard: clipboard,
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    await session.ensureStarted();
    expect(session.isRunning, isTrue);
    feedTerminalInputForTesting(session, 'probe');
    expect(utf8.decode(fakeSession.writes.single), 'probe');
    fakeSession.writes.clear();

    await pasteTerminalClipboardForTesting(session);

    expect(utf8.decode(fakeSession.writes.single), '/tmp/alera-paste.png');
    expect(clipboard.imageReadCount, 1);
  });

  test('bracketed-pastes image paths when the foreground enables it', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fakeSession = _FakeTerminalPtySession();
    final clipboard = _FakeTerminalClipboard(
      text: '',
      imagePath: r'C:\Users\Alera User\image $&".png',
    );
    final runtime = XtermTerminalRuntime(
      terminalClipboard: clipboard,
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    await session.ensureStarted();
    writeTerminalOutputForTesting(session, '\x1b[?2004h');

    await pasteTerminalClipboardForTesting(session);

    expect(
      utf8.decode(fakeSession.writes.single),
      '\x1b[200~${r'C:\Users\Alera User\image $&".png'}\x1b[201~',
    );
  });

  test('falls back to an image when the clipboard text read fails', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fakeSession = _FakeTerminalPtySession();
    final clipboard = _FakeTerminalClipboard(imagePath: '/tmp/alera-paste.png')
      ..readError = StateError('No text flavor');
    final runtime = XtermTerminalRuntime(
      terminalClipboard: clipboard,
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    await session.ensureStarted();

    await pasteTerminalClipboardForTesting(session);

    expect(utf8.decode(fakeSession.writes.single), '/tmp/alera-paste.png');
    expect(clipboard.imageReadCount, 1);
  });

  test('copy-on-select writes the settled local selection', () async {
    final clipboard = _FakeTerminalClipboard();
    final runtime = XtermTerminalRuntime(
      terminalClipboard: clipboard,
      initialSettings: TerminalSettings.defaults.copyWith(
        clipboardOnSelect: true,
      ),
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    writeTerminalOutputForTesting(session, 'selected text');

    selectTerminalRangeForTesting(
      session,
      const xterm.CellOffset(0, 0),
      const xterm.CellOffset(8, 0),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(clipboard.writes, <String>['selected']);
  });
}
