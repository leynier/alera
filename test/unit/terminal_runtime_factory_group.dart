part of 'terminal_runtime_native_test.dart';

void _registerTerminalRuntimeFactoryGroup() {
  group('DefaultTerminalPtySessionFactory', () {
    test('chooses posix on desktop and ghostty elsewhere', () async {
      final factory = const DefaultTerminalPtySessionFactory();
      TerminalPtySession? posix;
      TerminalPtySession? ghostty;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        posix = factory.create(
          sessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
        );
        expect(posix.runtimeType.toString(), contains('Posix'));
        expect(posix.startedNewProcess, isFalse);
        posix.dispose();
        await expectLater(
          posix.start(
            launch: _launch('noop', shell: '/bin/sh'),
            workingDirectory: '/tmp',
            cols: 80,
            rows: 24,
          ),
          throwsStateError,
        );

        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        ghostty = factory.create(
          sessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
        );
        expect(ghostty.runtimeType.toString(), contains('Ghostty'));
        expect(ghostty.startedNewProcess, isFalse);
        expect(ghostty.writeBytes(const <int>[]), isFalse);
        ghostty.resize(100, 30, 8, 16);
        ghostty.dispose();
        ghostty.dispose();
        await expectLater(
          ghostty.start(
            launch: _launch('noop', shell: '/bin/sh'),
            workingDirectory: '/tmp',
            cols: 80,
            rows: 24,
          ),
          throwsStateError,
        );
      } finally {
        posix?.dispose();
        ghostty?.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test(
      'direct adapter helpers translate events and guard disposed sessions',
      () async {
        final posix = createPosixPtySessionForTesting();
        final ghostty = createGhosttyPtySessionForTesting();
        addTearDown(posix.dispose);
        addTearDown(ghostty.dispose);

        final posixEvents = <TerminalPtySessionEvent>[];
        final posixSub = posix.events.listen(posixEvents.add);
        addTearDown(posixSub.cancel);
        final ghosttyEvents = <TerminalPtySessionEvent>[];
        final ghosttySub = ghostty.events.listen(ghosttyEvents.add);
        addTearDown(ghosttySub.cancel);

        expect(posix.writeBytes(const <int>[]), isFalse);
        posix.resize(80, 24, 8, 16);
        handlePosixReadMessageForTesting(posix, Uint8List.fromList(<int>[65]));
        handlePosixReadMessageForTesting(posix, <Object?, Object?>{
          'type': 'error',
          'error': 'boom',
        });
        handlePosixReadMessageForTesting(posix, const <Object?, Object?>{
          'type': 'done',
        });
        await Future<void>.delayed(Duration.zero);

        expect(posixEvents.whereType<TerminalPtyOutputEvent>(), hasLength(1));
        expect(posixEvents.whereType<TerminalPtyErrorEvent>(), hasLength(1));
        expect(
          posixEvents.whereType<TerminalPtyExitEvent>().single.exitCode,
          0,
        );

        expect(ghostty.writeBytes(const <int>[]), isFalse);
        ghostty.resize(80, 24, 8, 16);
        handleGhosttyEventForTesting(
          ghostty,
          GhosttyTerminalPtyOutputEvent(Uint8List.fromList(<int>[66])),
        );
        handleGhosttyEventForTesting(
          ghostty,
          const GhosttyTerminalPtyExitEvent(7),
        );
        handleGhosttyEventForTesting(
          ghostty,
          const GhosttyTerminalPtyErrorEvent('boom'),
        );
        handleGhosttyEventForTesting(
          ghostty,
          const GhosttyTerminalPtyStateChangeEvent(
            GhosttyTerminalPtySessionState.idle,
            GhosttyTerminalPtySessionState.running,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(ghosttyEvents.whereType<TerminalPtyOutputEvent>(), hasLength(1));
        expect(
          ghosttyEvents.whereType<TerminalPtyExitEvent>().single.exitCode,
          7,
        );
        expect(ghosttyEvents.whereType<TerminalPtyErrorEvent>(), hasLength(1));

        posix.dispose();
        ghostty.dispose();
        posix.terminate();
        ghostty.terminate();

        await expectLater(
          posix.start(
            launch: _launch('noop', shell: '/bin/sh'),
            workingDirectory: '/tmp',
            cols: 80,
            rows: 24,
          ),
          throwsStateError,
        );
        await expectLater(
          ghostty.start(
            launch: _launch('noop', shell: '/bin/sh'),
            workingDirectory: '/tmp',
            cols: 80,
            rows: 24,
          ),
          throwsStateError,
        );
      },
    );

    test('adapter start failures bubble for missing shells', () async {
      final posix = createPosixPtySessionForTesting();
      final ghostty = createGhosttyPtySessionForTesting();
      addTearDown(posix.dispose);
      addTearDown(ghostty.dispose);

      await expectLater(
        posix.start(
          launch: _launch('missing', shell: '/definitely/missing-shell'),
          workingDirectory: '/tmp',
          cols: 80,
          rows: 24,
        ),
        throwsA(anything),
      );
      await expectLater(
        ghostty.start(
          launch: _launch('missing', shell: '/definitely/missing-shell'),
          workingDirectory: '/tmp',
          cols: 80,
          rows: 24,
        ),
        throwsA(anything),
      );
    });

    test(
      'real posix adapter starts, writes, resizes, and exits',
      () async {
        if (!Platform.isMacOS && !Platform.isLinux) {
          return;
        }
        final session = createPosixPtySessionForTesting();
        addTearDown(session.dispose);
        final output = StringBuffer();
        final readyCompleter = Completer<void>();
        final exitCompleter = Completer<void>();
        final events = <TerminalPtySessionEvent>[];
        final sub = session.events.listen((event) {
          events.add(event);
          switch (event) {
            case TerminalPtyOutputEvent(:final data):
              output.write(utf8.decode(data, allowMalformed: true));
              if (output.toString().contains('ready-posix') &&
                  !readyCompleter.isCompleted) {
                readyCompleter.complete();
              }
            case TerminalPtySnapshotEvent():
              break;
            case TerminalPtyExitEvent():
              if (!exitCompleter.isCompleted) {
                exitCompleter.complete();
              }
            case TerminalPtyErrorEvent():
              break;
          }
        });
        addTearDown(sub.cancel);

        await session.start(
          launch: _launch(
            'shell',
            shell: '/bin/sh',
            arguments: const <String>[
              '-c',
              'printf ready-posix; IFS= read -r line; printf runtime-posix; exit 0',
            ],
          ),
          workingDirectory: '/tmp',
          cols: 80,
          rows: 24,
        );
        expect(session.startedNewProcess, isTrue);
        await readyCompleter.future.timeout(const Duration(seconds: 10));

        session.resize(100, 30, 8, 16);
        expect(session.writeBytes(utf8.encode('go\r')), isTrue);
        await exitCompleter.future.timeout(const Duration(seconds: 10));

        expect(output.toString(), contains('runtime-posix'));
        expect(
          events.whereType<TerminalPtyExitEvent>().single.exitCode,
          equals(0),
        );
        expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
      },
      skip: _skipLinuxCiRealPtyReason,
    );

    test(
      'real ghostty adapter starts, writes, resizes, and exits',
      () async {
        if (!Platform.isMacOS && !Platform.isLinux) {
          return;
        }
        final session = createGhosttyPtySessionForTesting();
        addTearDown(session.dispose);
        final output = StringBuffer();
        final readyCompleter = Completer<void>();
        final exitCompleter = Completer<void>();
        final events = <TerminalPtySessionEvent>[];
        final sub = session.events.listen((event) {
          events.add(event);
          switch (event) {
            case TerminalPtyOutputEvent(:final data):
              output.write(utf8.decode(data, allowMalformed: true));
              if (output.toString().contains('ready-ghostty') &&
                  !readyCompleter.isCompleted) {
                readyCompleter.complete();
              }
            case TerminalPtySnapshotEvent():
              break;
            case TerminalPtyExitEvent():
              if (!exitCompleter.isCompleted) {
                exitCompleter.complete();
              }
            case TerminalPtyErrorEvent():
              break;
          }
        });
        addTearDown(sub.cancel);

        await session.start(
          launch: _launch(
            'shell',
            shell: '/bin/sh',
            arguments: const <String>[
              '-c',
              'printf ready-ghostty; IFS= read -r line; printf runtime-ghostty; exit 0',
            ],
          ),
          workingDirectory: '/tmp',
          cols: 80,
          rows: 24,
        );
        expect(session.startedNewProcess, isTrue);
        await readyCompleter.future.timeout(const Duration(seconds: 10));

        session.resize(100, 30, 8, 16);
        expect(session.writeBytes(utf8.encode('go\r')), isTrue);
        await exitCompleter.future.timeout(const Duration(seconds: 10));

        expect(output.toString(), contains('runtime-ghostty'));
        expect(
          events.whereType<TerminalPtyExitEvent>().single.exitCode,
          equals(0),
        );
        expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
      },
      skip: _skipLinuxCiRealPtyReason,
    );
  });
}
