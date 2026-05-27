import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/gestures.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:xterm/xterm.dart' as xterm;

void main() {
  group('terminal runtime helpers', () {
    test(
      'platform, font, separator, cursor, and color helpers cover branches',
      () {
        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.macOS,
          ),
          isTrue,
        );
        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.iOS,
          ),
          isFalse,
        );
        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.macOS,
            isWeb: true,
          ),
          isFalse,
        );

        expect(
          xtermTargetPlatformForTesting(TargetPlatform.macOS),
          xterm.TerminalTargetPlatform.macos,
        );
        expect(
          xtermTargetPlatformForTesting(TargetPlatform.windows),
          xterm.TerminalTargetPlatform.windows,
        );
        expect(
          xtermTargetPlatformForTesting(TargetPlatform.linux),
          xterm.TerminalTargetPlatform.linux,
        );
        expect(
          xtermTargetPlatformForTesting(TargetPlatform.android),
          xterm.TerminalTargetPlatform.android,
        );
        expect(
          xtermTargetPlatformForTesting(TargetPlatform.iOS),
          xterm.TerminalTargetPlatform.ios,
        );
        expect(
          xtermTargetPlatformForTesting(TargetPlatform.fuchsia),
          xterm.TerminalTargetPlatform.fuchsia,
        );
        expect(
          defaultXtermTargetPlatformForTesting(),
          xtermTargetPlatformForTesting(defaultTargetPlatform),
        );

        expect(resolveTerminalFontFamilyForTesting('  '), 'monospace');
        expect(resolveTerminalFontFamilyForTesting('Fira Code'), 'Fira Code');
        expect(
          terminalFontFallbackForTesting(),
          containsAll(<String>['SF Mono', 'monospace']),
        );

        expect(wordSeparatorsFromSettingsForTesting(null), isNull);
        expect(wordSeparatorsFromSettingsForTesting('   '), isNull);
        expect(
          wordSeparatorsFromSettingsForTesting(' ,|'),
          unorderedEquals(',|'.runes.toSet()),
        );

        expect(
          xtermCursorTypeForTesting(TerminalCursorShape.bar),
          xterm.TerminalCursorType.verticalBar,
        );
        expect(
          xtermCursorTypeForTesting(TerminalCursorShape.underline),
          xterm.TerminalCursorType.underline,
        );

        expect(colorFromHexForTesting('#112233'), const Color(0xFF112233));
        expect(colorFromHexForTesting(null), isNull);
        final theme = resolveXtermThemeForTesting(
          TerminalSettings.defaults.copyWith(
            cursorOpacity: 0.4,
            colorOverrides: const TerminalColorOverrides(
              cursor: '#336699',
              selection: '#112233',
              foreground: '#abcdef',
              background: '#010203',
            ),
          ),
        );
        expect(theme.selection, const Color(0xFF112233));
        expect(theme.foreground, const Color(0xFFABCDEF));
        expect(theme.background, const Color(0xFF010203));

        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.linux,
          ),
          isTrue,
        );
        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.windows,
          ),
          isTrue,
        );
        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.android,
          ),
          isFalse,
        );
        expect(
          isSupportedNativeDesktopTerminalPlatformForTesting(
            TargetPlatform.fuchsia,
          ),
          isFalse,
        );
        expect(
          terminalPlatformEnvironmentForTesting(),
          isNot(contains('NO_COLOR')),
        );
        final shellLaunches = terminalShellLaunchesForTesting();
        expect(shellLaunches, isNotEmpty);
        expect(
          shellLaunches
              .map(
                (launch) =>
                    '${launch.shell}\u0000${launch.arguments.join('\u0000')}',
              )
              .toSet()
              .length,
          shellLaunches.length,
        );
        expect(cmdQuoteForTesting('a"b'), '"a""b"');
        expect(shQuoteForTesting(''), "''");
        expect(shQuoteForTesting("a'b"), "'a'\"'\"'b'");
      },
    );

    test(
      'launch helpers cover blank, shell, and cmd working-directory branches',
      () {
        final launch = _launch('shell', shell: '/bin/zsh');
        expect(launchInWorkingDirectoryForTesting(launch, '   '), same(launch));

        final shellLaunch = launchInWorkingDirectoryForTesting(
          _launch(
            'shell',
            shell: '/bin/zsh',
            arguments: const <String>['-l', '-i'],
          ),
          '/tmp/alera repo',
        );
        expect(shellLaunch.shell, '/bin/sh');
        expect(shellLaunch.arguments, hasLength(2));
        expect(shellLaunch.arguments.first, '-c');
        expect(shellLaunch.arguments.last, contains("cd '/tmp/alera repo'"));
        expect(
          shellLaunch.arguments.last,
          contains("exec '/bin/zsh' '-l' '-i'"),
        );

        final cmdLaunch = launchInWorkingDirectoryForTesting(
          _launch(
            'cmd',
            shell: r'C:\Windows\System32\cmd.exe',
            arguments: const <String>['/q'],
          ),
          r'C:\Users\Alera Workspace',
        );
        expect(cmdLaunch.shell, r'C:\Windows\System32\cmd.exe');
        expect(
          cmdLaunch.arguments,
          containsAllInOrder(<String>[
            '/q',
            '/d',
            '/s',
            '/k',
            'cd /d "C:\\Users\\Alera Workspace"',
          ]),
        );
      },
    );

    test(
      'agent hook launch env strips inherited metadata before injection',
      () {
        final launch = launchWithSanitizedAgentHookEnvironmentForTesting(
          _launch(
            'shell',
            shell: '/bin/zsh',
            environment: const <String, String>{
              'PATH': '/usr/bin',
              'ALERA_AGENT_HOOK_TOKEN': 'stale',
              'ALERA_TERMINAL_SESSION_ID': 'old-session',
              'ALERA_CODEX_HOME': '/old-runtime',
            },
          ),
          const <String, String>{
            'ALERA_AGENT_HOOK_TOKEN': 'fresh',
            'ALERA_TERMINAL_SESSION_ID': 'session-1',
            'ALERA_WORKSPACE_ID': 'workspace-1',
            'ALERA_TAB_ID': 'tab-1',
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
          },
        );

        expect(launch.environment, <String, String>{
          'PATH': '/usr/bin',
          'ALERA_AGENT_HOOK_TOKEN': 'fresh',
          'ALERA_TERMINAL_SESSION_ID': 'session-1',
          'ALERA_WORKSPACE_ID': 'workspace-1',
          'ALERA_TAB_ID': 'tab-1',
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        });
        expect(launch.setupCommand, isNull);

        final sanitizedOnly = launchWithSanitizedAgentHookEnvironmentForTesting(
          _launch(
            'shell',
            shell: '/bin/zsh',
            environment: const <String, String>{
              'ALERA_AGENT_HOOK_PORT': '123',
              'ALERA_CODEX_HOME': '/old-runtime',
              'USER': 'tester',
            },
          ),
          null,
        );
        expect(sanitizedOnly.environment, <String, String>{'USER': 'tester'});

        final existingSetupLaunch =
            launchWithSanitizedAgentHookEnvironmentForTesting(
              _launch(
                'shell',
                shell: '/bin/zsh',
                setupCommand: 'printf setup\n',
              ),
              const <String, String>{'ALERA_CODEX_HOME': '/runtime/codex'},
            );
        expect(existingSetupLaunch.setupCommand, 'printf setup\n');

        final unknownWithoutSetup =
            launchWithSanitizedAgentHookEnvironmentForTesting(
              _launch('unknown', shell: '/usr/local/bin/elvish'),
              const <String, String>{'ALERA_CODEX_HOME': '/runtime/codex'},
            );
        expect(unknownWithoutSetup.setupCommand, isNull);
      },
    );

    test('posix read helper covers invalid fds', () async {
      final receivePort = ReceivePort();
      addTearDown(receivePort.close);
      posixPtyReadIsolateForTesting(<Object?>[-1, receivePort.sendPort]);
      expect(await receivePort.first, const <Object?, Object?>{
        'type': 'error',
        'error': 'PTY master file descriptor is unavailable.',
      });
      expect(currentErrnoForTesting(), isA<int>());
    });

    test('posix read isolate sends done when the stream reaches eof', () async {
      final receivePort = ReceivePort();
      addTearDown(receivePort.close);
      final path = '/dev/null'.toNativeUtf8();
      late final int fd;

      try {
        fd = _openForTesting(path, _oRdOnly);
      } finally {
        calloc.free(path);
      }
      expect(fd, isNonNegative);
      addTearDown(() => _closeForTesting(fd));

      posixPtyReadIsolateForTesting(<Object?>[fd, receivePort.sendPort]);

      expect(await receivePort.first, const <Object?, Object?>{'type': 'done'});
    });

    test(
      'posix read isolate reports reader failures through the send port',
      () async {
        final receivePort = ReceivePort();
        addTearDown(receivePort.close);

        runPosixPtyReadIsolateForTesting(
          fd: 1,
          sendPort: receivePort.sendPort,
          read: (_, _, _) => throw StateError('boom'),
        );

        expect(await receivePort.first, <Object?, Object?>{
          'type': 'error',
          'error': 'Bad state: boom',
        });
      },
    );

    test(
      'pty write and resize helpers convert thrown errors to events',
      () async {
        final events = StreamController<TerminalPtySessionEvent>.broadcast();
        addTearDown(events.close);
        final emitted = <TerminalPtySessionEvent>[];
        final sub = events.stream.listen(emitted.add);
        addTearDown(sub.cancel);

        expect(
          writePtyBytesForTesting(
            bytes: const <int>[1],
            write: (_) => throw StateError('write failed'),
            events: events,
          ),
          isFalse,
        );
        resizePtyForTesting(
          rows: 24,
          cols: 80,
          resize: ({required rows, required cols}) =>
              throw StateError('resize failed'),
          events: events,
        );
        await Future<void>.delayed(Duration.zero);

        expect(emitted.whereType<TerminalPtyErrorEvent>(), hasLength(2));
      },
    );
  });

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

    test('real posix adapter starts, writes, resizes, and exits', () async {
      if (!Platform.isMacOS && !Platform.isLinux) {
        return;
      }
      final session = createPosixPtySessionForTesting();
      addTearDown(session.dispose);
      final output = StringBuffer();
      final exitCompleter = Completer<void>();
      final events = <TerminalPtySessionEvent>[];
      final sub = session.events.listen((event) {
        events.add(event);
        switch (event) {
          case TerminalPtyOutputEvent(:final data):
            output.write(utf8.decode(data, allowMalformed: true));
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
        launch: _launch('shell', shell: '/bin/sh'),
        workingDirectory: '/tmp',
        cols: 80,
        rows: 24,
      );
      expect(session.startedNewProcess, isTrue);

      session.resize(100, 30, 8, 16);
      expect(
        session.writeBytes(utf8.encode('printf runtime-posix\nexit\n')),
        isTrue,
      );
      await exitCompleter.future.timeout(const Duration(seconds: 10));

      expect(output.toString(), contains('runtime-posix'));
      expect(
        events.whereType<TerminalPtyExitEvent>().single.exitCode,
        equals(0),
      );
      expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
    });

    test('real ghostty adapter starts, writes, resizes, and exits', () async {
      if (!Platform.isMacOS && !Platform.isLinux) {
        return;
      }
      final session = createGhosttyPtySessionForTesting();
      addTearDown(session.dispose);
      final output = StringBuffer();
      final exitCompleter = Completer<void>();
      final events = <TerminalPtySessionEvent>[];
      final sub = session.events.listen((event) {
        events.add(event);
        switch (event) {
          case TerminalPtyOutputEvent(:final data):
            output.write(utf8.decode(data, allowMalformed: true));
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
        launch: _launch('shell', shell: '/bin/sh'),
        workingDirectory: '/tmp',
        cols: 80,
        rows: 24,
      );
      expect(session.startedNewProcess, isTrue);

      session.resize(100, 30, 8, 16);
      expect(
        session.writeBytes(utf8.encode('printf runtime-ghostty\nexit\n')),
        isTrue,
      );
      await exitCompleter.future.timeout(const Duration(seconds: 10));

      expect(output.toString(), contains('runtime-ghostty'));
      expect(
        events.whereType<TerminalPtyExitEvent>().single.exitCode,
        equals(0),
      );
      expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
    });
  });

  group('XtermTerminalRuntime', () {
    test(
      'reuses sessions, syncs metadata, and flushes pending resizes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final startCompleter = Completer<void>();
        final fakeSession = _FakeTerminalPtySession(
          startCompleter: startCompleter,
        );
        final factory = _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[fakeSession],
        );
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('shell', shell: '/bin/sh'),
          ],
        );
        addTearDown(runtime.dispose);
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );
        var notifications = 0;
        session.addListener(() => notifications++);
        try {
          expect(session.tabId, 'tab-1');
          expect(session.workspaceId, 'workspace-1');
          expect(session.displayTitle, 'Terminal 1');
          expect(session.isStarting, isFalse);
          expect(session.errorMessage, isNull);

          setTerminalTitleForTesting(session, 'Runtime title');
          expect(session.displayTitle, 'Runtime title');

          final firstStart = session.ensureStarted();
          final secondStart = session.ensureStarted();
          expect(session.isStarting, isTrue);
          startCompleter.complete();
          await Future.wait(<Future<void>>[firstStart, secondStart]);
          await session.ensureStarted();

          expect(factory.createdSessions, hasLength(1));
          expect(session.isRunning, isTrue);

          handleTerminalResizeForTesting(session, 120, 40, 8, 16);
          flushPendingPtyResizeForTesting(session);
          expect(fakeSession.resizeCalls, <_ResizeCall>[
            const _ResizeCall(
              cols: 120,
              rows: 40,
              cellWidthPx: 8,
              cellHeightPx: 16,
            ),
          ]);

          writeTerminalOutputForTesting(session, 'hello');
          writeTerminalOutputForTesting(session, '');

          final updatedSession = runtime.sessionFor(
            workspace: _workspace(path: '/repo/updated'),
            tab: _tab(
              title: 'Pinned title',
              payload: const <String, Object?>{
                workspaceTabManualTitlePayloadKey: true,
              },
            ),
          );
          await Future<void>.delayed(Duration.zero);

          expect(identical(updatedSession, session), isTrue);
          expect(session.displayTitle, 'Pinned title');
          expect(notifications, greaterThan(0));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test(
      'closes tabs and workspaces without disposing unrelated sessions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final first = _FakeTerminalPtySession();
        final second = _FakeTerminalPtySession();
        final third = _FakeTerminalPtySession();
        final factory = _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[first, second, third],
        );
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('shell', shell: '/bin/sh'),
          ],
        );
        addTearDown(runtime.dispose);
        try {
          final firstSession = runtime.sessionFor(
            workspace: _workspace(),
            tab: _tab(),
          );
          final secondSession = runtime.sessionFor(
            workspace: _workspace(),
            tab: _tab(id: 'tab-2', title: 'Terminal 2'),
          );
          final thirdSession = runtime.sessionFor(
            workspace: _workspace(id: 'workspace-2', path: '/repo/other'),
            tab: _tab(
              id: 'tab-3',
              workspaceId: 'workspace-2',
              title: 'Terminal 3',
            ),
          );

          await firstSession.ensureStarted();
          await secondSession.ensureStarted();
          await thirdSession.ensureStarted();

          runtime.closeTab('tab-1');
          await Future<void>.delayed(Duration.zero);
          expect(first.disposed, isTrue);
          expect(first.terminated, isTrue);
          expect(second.disposed, isFalse);
          expect(third.disposed, isFalse);

          runtime.closeWorkspace('workspace-1');
          await Future<void>.delayed(Duration.zero);
          expect(second.disposed, isTrue);
          expect(second.terminated, isTrue);
          expect(third.disposed, isFalse);

          runtime.dispose();
          await Future<void>.delayed(Duration.zero);
          expect(third.disposed, isTrue);
          expect(third.terminated, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test(
      'unsupported mobile platforms fail before creating PTY sessions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final factory = _FakeTerminalPtySessionFactory();
          final runtime = XtermTerminalRuntime(
            ptySessionFactory: factory,
            shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
              _launch('noop', shell: '/bin/sh'),
            ],
          );
          addTearDown(runtime.dispose);
          final session = runtime.sessionFor(
            workspace: _workspace(),
            tab: _tab(),
          );

          await session.ensureStarted();

          expect(factory.createdSessions, isEmpty);
          expect(session.isRunning, isFalse);
          expect(session.errorMessage, contains('native desktop PTY path'));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test(
      'falls back to the next shell launch and writes setup commands',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final first = _FakeTerminalPtySession(
          startError: StateError('first failed'),
        );
        final second = _FakeTerminalPtySession();
        final factory = _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[first, second],
        );
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('first', shell: '/bin/first'),
            _launch(
              'second',
              shell: '/bin/second',
              arguments: const <String>['-l'],
              setupCommand: 'printf setup\n',
            ),
          ],
        );
        addTearDown(runtime.dispose);
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );
        try {
          final startFuture = session.ensureStarted();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await startFuture;

          expect(session.errorMessage, isNull);
          expect(session.isRunning, isTrue);
          expect(first.disposed, isTrue);
          expect(second.startedLaunch, isNotNull);
          expect(second.startedLaunch!.label, 'second');
          expect(second.startedLaunch!.shell, '/bin/sh');
          expect(
            second.startedLaunch!.arguments.last,
            contains(_workspace().path),
          );
          expect(
            second.writes.map(utf8.decode).join(),
            contains('printf setup\n'),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test(
      'prepares Codex launches without writing restore setup commands',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final fakeSession = _FakeTerminalPtySession();
        final shellStartupPreparer = _RecordingTerminalShellStartupPreparer();
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: _FakeTerminalPtySessionFactory(
            sessions: <_FakeTerminalPtySession>[fakeSession],
          ),
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('shell', shell: '/bin/zsh', setupCommand: 'printf setup\n'),
          ],
          shellStartupPreparer: shellStartupPreparer,
          agentHookEnvironmentBuilder:
              ({
                required terminalSessionId,
                required workspaceId,
                required tabId,
              }) {
                return const <String, String>{
                  'CODEX_HOME': '/runtime/codex',
                  'ALERA_CODEX_HOME': '/runtime/codex',
                };
              },
        );
        addTearDown(runtime.dispose);
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );
        try {
          await session.ensureStarted();

          final startedSetupCommand = fakeSession.startedLaunch!.setupCommand;
          expect(startedSetupCommand, 'printf setup\n');
          final writtenSetupCommand = fakeSession.writes
              .map(utf8.decode)
              .join();
          expect(writtenSetupCommand, startedSetupCommand);
          expect(shellStartupPreparer.launches, hasLength(1));
          expect(
            shellStartupPreparer.launches.single.environment,
            containsPair('ALERA_CODEX_HOME', '/runtime/codex'),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test('surfaces a clear error when every shell launch fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[
          _FakeTerminalPtySession(startError: StateError('first failed')),
          _FakeTerminalPtySession(startError: StateError('second failed')),
        ],
      );
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('first', shell: '/bin/first'),
          _launch('second', shell: '/bin/second'),
        ],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      try {
        await session.ensureStarted();

        expect(factory.createdSessions, hasLength(2));
        expect(session.isRunning, isFalse);
        expect(
          session.errorMessage,
          contains('No desktop PTY shell could be started'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test(
      'does not replay setup commands when attaching existing sessions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final attached = _FakeTerminalPtySession()
          ..startedNewProcessValue = false;
        final factory = _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[attached],
        );
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('shell', shell: '/bin/sh', setupCommand: 'printf setup\n'),
          ],
        );
        addTearDown(runtime.dispose);
        try {
          final session = runtime.sessionFor(
            workspace: _workspace(),
            tab: _tab(
              payload: const <String, Object?>{
                workspaceTabTerminalSessionIdPayloadKey: 'session-1',
              },
            ),
          );

          await session.ensureStarted();

          expect(attached.startedWorkingDirectory, _workspace().path);
          expect(attached.writes, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test(
      'restart suppresses old generations and emits exits for the active one',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final first = _FakeTerminalPtySession();
        final second = _FakeTerminalPtySession();
        final factory = _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[first, second],
        );
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('shell', shell: '/bin/sh'),
          ],
        );
        addTearDown(runtime.dispose);
        final exits = <TerminalRuntimeExitEvent>[];
        final exitSub = runtime.exits.listen(exits.add);
        addTearDown(exitSub.cancel);
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );
        try {
          await session.ensureStarted();
          await session.restart();

          expect(factory.createdSessions, hasLength(2));
          expect(first.disposed, isTrue);
          expect(session.isRunning, isTrue);
          expect(exits, isEmpty);

          first.emitExit(9);
          await Future<void>.delayed(Duration.zero);
          expect(exits, isEmpty);

          second.emitExit(5);
          await Future<void>.delayed(Duration.zero);

          expect(exits, hasLength(1));
          expect(exits.single.exitCode, 5);
          expect(session.isRunning, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'build view supports deferred focus, direct input, and OSC updates',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final fakeSession = _FakeTerminalPtySession();
        final factory = _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[fakeSession],
        );
        final launcher = _FakeExternalUriLauncher();
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          externalUriLauncher: launcher,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('shell', shell: '/bin/sh'),
          ],
        );
        addTearDown(runtime.dispose);
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(child: session.buildView(autofocus: false)),
            ),
          ),
        );
        try {
          await tester.pump();

          await session.ensureStarted();
          feedTerminalInputForTesting(session, 'abc');
          expect(fakeSession.writes.map(utf8.decode).join(), contains('abc'));

          final focusNode = terminalFocusNodeForTesting(session);
          expect(focusNode.hasFocus, isFalse);
          expect(focusNode.canRequestFocus, isTrue);
          requestTerminalFocusNowForTesting(session);
          session.requestFocus();
          await tester.pump();
          await tester.pump();
          expect(focusNode.context, isNotNull);

          handlePrivateOscForTesting(session, '8', <String>[
            '',
            'https://example.com',
          ]);
          fakeSession.emitError(StateError('boom'));
          await tester.pump();

          expect(find.byType(xterm.TerminalView), findsOneWidget);
        } finally {
          runtime.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('build view clears hovered links on exit and session updates', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final launcher = _FakeExternalUriLauncher(
        error: StateError('cannot launch'),
      );
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[
            _FakeTerminalPtySession(),
            _FakeTerminalPtySession(),
          ],
        ),
        externalUriLauncher: launcher,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      final firstSession = runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab(id: 'tab-1'),
      );
      final secondSession = runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab(id: 'tab-2'),
      );

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: firstSession.buildView(autofocus: false),
              ),
            ),
          ),
        );
        await tester.pump();

        handlePrivateOscForTesting(firstSession, '8', <String>[
          '',
          'https://example.com',
        ]);
        writeTerminalOutputForTesting(firstSession, 'open');
        handlePrivateOscForTesting(firstSession, '8', const <String>['', '']);
        await tester.pump();

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        final linkOffset =
            tester.getTopLeft(find.byType(xterm.TerminalView)) +
            const Offset(8, 8);
        await mouse.moveTo(linkOffset);
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        final view = tester.widget<xterm.TerminalView>(
          find.byType(xterm.TerminalView),
        );
        view.onTapUp?.call(
          TapUpDetails(kind: PointerDeviceKind.mouse),
          const xterm.CellOffset(1, 0),
        );
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();

        expect(launcher.openedUris, <Uri>[Uri.parse('https://example.com')]);
        expect(
          find.text('Could not open link: https://example.com'),
          findsOneWidget,
        );

        await mouse.moveTo(const Offset(-10, -10));
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: secondSession.buildView(autofocus: false),
              ),
            ),
          ),
        );
        await tester.pump();
      } finally {
        runtime.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('build view forwards autofocus and key callbacks', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[_FakeTerminalPtySession()],
        ),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      try {
        KeyEvent? capturedEvent;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: session.buildView(
                  autofocus: true,
                  onKeyEvent: (_, event) {
                    capturedEvent = event;
                    return KeyEventResult.handled;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final view = tester.widget<xterm.TerminalView>(
          find.byType(xterm.TerminalView),
        );
        expect(view.autofocus, isTrue);
        expect(
          view.onKeyEvent?.call(
            FocusNode(),
            const KeyUpEvent(
              timeStamp: Duration.zero,
              physicalKey: PhysicalKeyboardKey.keyA,
              logicalKey: LogicalKeyboardKey.keyA,
            ),
          ),
          KeyEventResult.handled,
        );
        expect(capturedEvent, isA<KeyUpEvent>());
      } finally {
        runtime.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

GhosttyTerminalShellLaunch _launch(
  String label, {
  required String shell,
  List<String> arguments = const <String>[],
  Map<String, String> environment = const <String, String>{
    'TERM': 'xterm-256color',
  },
  String? setupCommand,
}) {
  return GhosttyTerminalShellLaunch(
    label: label,
    shell: shell,
    arguments: arguments,
    environment: environment,
    setupCommand: setupCommand,
  );
}

Workspace _workspace({String id = 'workspace-1', String path = '/repo/alera'}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: 'Main',
    branch: 'main',
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab({
  String id = 'tab-1',
  String workspaceId = 'workspace-1',
  String title = 'Terminal 1',
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    title: title,
    createdAt: now,
    updatedAt: now,
    payload: payload,
  );
}

class _FakeTerminalPtySessionFactory implements TerminalPtySessionFactory {
  _FakeTerminalPtySessionFactory({List<_FakeTerminalPtySession>? sessions})
    : _availableSessions = sessions ?? <_FakeTerminalPtySession>[];

  final List<_FakeTerminalPtySession> _availableSessions;
  final List<_FakeTerminalPtySession> createdSessions =
      <_FakeTerminalPtySession>[];

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    final session = _availableSessions.removeAt(0);
    createdSessions.add(session);
    return session;
  }
}

class _RecordingTerminalShellStartupPreparer
    implements TerminalShellStartupPreparer {
  final List<GhosttyTerminalShellLaunch> launches =
      <GhosttyTerminalShellLaunch>[];

  @override
  GhosttyTerminalShellLaunch prepare(GhosttyTerminalShellLaunch launch) {
    launches.add(launch);
    return launch;
  }
}

class _FakeTerminalPtySession implements TerminalPtySession {
  _FakeTerminalPtySession({this.startError, this.startCompleter});

  final Object? startError;
  final Completer<void>? startCompleter;
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  final List<_ResizeCall> resizeCalls = <_ResizeCall>[];
  GhosttyTerminalShellLaunch? startedLaunch;
  String? startedWorkingDirectory;
  int? startedCols;
  int? startedRows;
  bool disposed = false;
  bool terminated = false;
  bool startedNewProcessValue = true;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => startedNewProcessValue;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
  }) async {
    startedLaunch = launch;
    startedWorkingDirectory = workingDirectory;
    startedCols = cols;
    startedRows = rows;
    if (startError case final Object error) {
      throw error;
    }
    if (startCompleter case final completer?) {
      await completer.future;
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    writes.add(List<int>.from(bytes));
    return bytes.isNotEmpty;
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    resizeCalls.add(
      _ResizeCall(
        cols: cols,
        rows: rows,
        cellWidthPx: cellWidthPx,
        cellHeightPx: cellHeightPx,
      ),
    );
  }

  void emitOutput(List<int> data) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyOutputEvent(Uint8List.fromList(data)));
  }

  void emitExit(int exitCode) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyExitEvent(exitCode));
  }

  void emitError(Object error) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyErrorEvent(error));
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    unawaited(_events.close());
  }

  @override
  void terminate() {
    terminated = true;
    dispose();
  }
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  _FakeExternalUriLauncher({this.error});

  final Object? error;
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    openedUris.add(uri);
    if (error case final Object error) {
      throw error;
    }
  }
}

class _ResizeCall {
  const _ResizeCall({
    required this.cols,
    required this.rows,
    required this.cellWidthPx,
    required this.cellHeightPx,
  });

  final int cols;
  final int rows;
  final int cellWidthPx;
  final int cellHeightPx;

  @override
  bool operator ==(Object other) {
    return other is _ResizeCall &&
        other.cols == cols &&
        other.rows == rows &&
        other.cellWidthPx == cellWidthPx &&
        other.cellHeightPx == cellHeightPx;
  }

  @override
  int get hashCode => Object.hash(cols, rows, cellWidthPx, cellHeightPx);
}

const int _oRdOnly = 0;

final ffi.DynamicLibrary _libcForTesting = ffi.DynamicLibrary.process();
final int Function(ffi.Pointer<Utf8>, int) _openForTesting = _libcForTesting
    .lookupFunction<_OpenNative, _OpenDart>('open');
final int Function(int) _closeForTesting = _libcForTesting
    .lookupFunction<_CloseNative, _CloseDart>('close');

typedef _OpenNative = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef _OpenDart = int Function(ffi.Pointer<Utf8>, int);
typedef _CloseNative = ffi.Int32 Function(ffi.Int32);
typedef _CloseDart = int Function(int);
