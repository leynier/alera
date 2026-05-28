part of 'terminal_runtime_native_test.dart';

void _registerTerminalRuntimeHelperGroup() {
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
              'PATH': '/old-wrapper:/usr/bin',
              'ALERA_AGENT_HOOK_TOKEN': 'stale',
              'ALERA_TERMINAL_SESSION_ID': 'old-session',
              'ALERA_CODEX_HOME': '/old-runtime',
              'ALERA_CLAUDE_CONFIG_DIR': '/old-claude-runtime',
              'COPILOT_HOME': '/old-copilot-overlay',
              'ALERA_COPILOT_HOME': '/old-copilot-overlay',
              'ALERA_COPILOT_SOURCE_HOME': '/user-copilot',
              'OPENCODE_CONFIG_DIR': '/old-opencode-overlay',
              'ALERA_OPENCODE_CONFIG_DIR': '/old-opencode-overlay',
              'ALERA_OPENCODE_SOURCE_CONFIG_DIR': '/user-opencode',
              'PI_CODING_AGENT_DIR': '/old-pi-overlay',
              'ALERA_PI_CODING_AGENT_DIR': '/old-pi-overlay',
              'ALERA_CURSOR_PLUGIN_DIR': '/old-cursor-plugin',
              'ALERA_AMP_CONFIG_DIR': '/old-amp-overlay',
              'ALERA_AMP_SOURCE_CONFIG_DIR': '/user-amp',
              'ALERA_AGENT_WRAPPER_PATH': '/old-wrapper',
            },
          ),
          const <String, String>{
            'ALERA_AGENT_HOOK_TOKEN': 'fresh',
            'ALERA_TERMINAL_SESSION_ID': 'session-1',
            'ALERA_WORKSPACE_ID': 'workspace-1',
            'ALERA_TAB_ID': 'tab-1',
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
            'CLAUDE_CONFIG_DIR': '/runtime/claude',
            'ALERA_CLAUDE_CONFIG_DIR': '/runtime/claude',
            'COPILOT_HOME': '/runtime/copilot',
            'ALERA_COPILOT_HOME': '/runtime/copilot',
            'ALERA_COPILOT_SOURCE_HOME': '/user-copilot',
            'OPENCODE_CONFIG_DIR': '/runtime/opencode',
            'ALERA_OPENCODE_CONFIG_DIR': '/runtime/opencode',
            'ALERA_OPENCODE_SOURCE_CONFIG_DIR': '/user-opencode',
            'PI_CODING_AGENT_DIR': '/runtime/pi',
            'ALERA_PI_CODING_AGENT_DIR': '/runtime/pi',
            'ALERA_CURSOR_PLUGIN_DIR': '/runtime/cursor-plugin',
            'ALERA_AMP_CONFIG_DIR': '/runtime/amp',
            'ALERA_AMP_SOURCE_CONFIG_DIR': '/user-amp',
            'ALERA_AGENT_WRAPPER_PATH': '/runtime/wrappers',
          },
        );

        expect(launch.environment, <String, String>{
          'PATH': '/runtime/wrappers:/usr/bin',
          'ALERA_AGENT_HOOK_TOKEN': 'fresh',
          'ALERA_TERMINAL_SESSION_ID': 'session-1',
          'ALERA_WORKSPACE_ID': 'workspace-1',
          'ALERA_TAB_ID': 'tab-1',
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
          'CLAUDE_CONFIG_DIR': '/runtime/claude',
          'ALERA_CLAUDE_CONFIG_DIR': '/runtime/claude',
          'COPILOT_HOME': '/runtime/copilot',
          'ALERA_COPILOT_HOME': '/runtime/copilot',
          'ALERA_COPILOT_SOURCE_HOME': '/user-copilot',
          'OPENCODE_CONFIG_DIR': '/runtime/opencode',
          'ALERA_OPENCODE_CONFIG_DIR': '/runtime/opencode',
          'ALERA_OPENCODE_SOURCE_CONFIG_DIR': '/user-opencode',
          'PI_CODING_AGENT_DIR': '/runtime/pi',
          'ALERA_PI_CODING_AGENT_DIR': '/runtime/pi',
          'ALERA_CURSOR_PLUGIN_DIR': '/runtime/cursor-plugin',
          'ALERA_AMP_CONFIG_DIR': '/runtime/amp',
          'ALERA_AMP_SOURCE_CONFIG_DIR': '/user-amp',
          'ALERA_AGENT_WRAPPER_PATH': '/runtime/wrappers',
        });
        expect(launch.setupCommand, isNull);

        final sanitizedOnly = launchWithSanitizedAgentHookEnvironmentForTesting(
          _launch(
            'shell',
            shell: '/bin/zsh',
            environment: const <String, String>{
              'PATH': '/old-wrapper:/usr/bin',
              'ALERA_AGENT_HOOK_PORT': '123',
              'ALERA_CODEX_HOME': '/old-runtime',
              'ALERA_CLAUDE_CONFIG_DIR': '/old-claude-runtime',
              'COPILOT_HOME': '/old-copilot-overlay',
              'ALERA_COPILOT_HOME': '/old-copilot-overlay',
              'ALERA_COPILOT_SOURCE_HOME': '/user-copilot',
              'OPENCODE_CONFIG_DIR': '/old-opencode-overlay',
              'ALERA_OPENCODE_CONFIG_DIR': '/old-opencode-overlay',
              'ALERA_OPENCODE_SOURCE_CONFIG_DIR': '/user-opencode',
              'PI_CODING_AGENT_DIR': '/old-pi-overlay',
              'ALERA_PI_CODING_AGENT_DIR': '/old-pi-overlay',
              'ALERA_CURSOR_PLUGIN_DIR': '/old-cursor-plugin',
              'ALERA_AMP_CONFIG_DIR': '/old-amp-overlay',
              'ALERA_AMP_SOURCE_CONFIG_DIR': '/user-amp',
              'ALERA_AGENT_WRAPPER_PATH': '/old-wrapper',
              'USER': 'tester',
            },
          ),
          null,
        );
        expect(sanitizedOnly.environment, <String, String>{
          'PATH': '/usr/bin',
          'COPILOT_HOME': '/user-copilot',
          'OPENCODE_CONFIG_DIR': '/user-opencode',
          'USER': 'tester',
        });

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
}
