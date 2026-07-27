part of 'terminal_runtime_native_test.dart';

void _registerTerminalLoginShellGroup() {
  group('terminal login shell launches', () {
    test('login shell conversion adds the flag the shell understands', () {
      final zsh = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'user shell',
          shell: '/bin/zsh',
          arguments: <String>['-i'],
        ),
      );
      expect(zsh.arguments, <String>['-l', '-i']);
      expect(zsh.shell, '/bin/zsh');

      final fish = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'user shell',
          shell: '/opt/homebrew/bin/fish',
          arguments: <String>['-i'],
        ),
      );
      expect(fish.arguments, <String>['--login', '-i']);

      final unknown = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'user shell',
          shell: '/usr/local/bin/exoticsh',
          arguments: <String>['-i'],
        ),
      );
      expect(unknown.arguments, <String>['-i']);
    });

    test('login shell conversion leaves rc-skipping profiles untouched', () {
      final cleanZsh = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'clean zsh shell',
          shell: '/bin/zsh',
          arguments: <String>['-f', '-i'],
        ),
      );
      expect(cleanZsh.arguments, <String>['-f', '-i']);

      final cleanBash = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'clean bash shell',
          shell: '/bin/bash',
          arguments: <String>['--noprofile', '--norc', '-i'],
        ),
      );
      expect(cleanBash.arguments, <String>['--noprofile', '--norc', '-i']);

      final alreadyLogin = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'user shell',
          shell: '/bin/zsh',
          arguments: <String>['-l', '-i'],
        ),
      );
      expect(alreadyLogin.arguments, <String>['-l', '-i']);

      final cmd = launchAsLoginShellForTesting(
        const GhosttyTerminalShellLaunch(
          label: 'cmd.exe',
          shell: r'C:\Windows\System32\cmd.exe',
        ),
      );
      expect(cmd.arguments, isEmpty);
    });

    test('login shell launch composes into the working directory exec', () {
      final launch = launchInWorkingDirectoryForTesting(
        launchAsLoginShellForTesting(
          const GhosttyTerminalShellLaunch(
            label: 'user shell',
            shell: '/bin/zsh',
            arguments: <String>['-i'],
          ),
        ),
        '/repo',
      );

      expect(launch.shell, '/bin/sh');
      expect(launch.arguments, <String>[
        '-c',
        "cd '/repo' || true; exec '/bin/zsh' '-l' '-i'",
      ]);
    });

    test('missing SHELL resolves a real login shell, not an rc-skipping one', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final launches = resolvedLoginShellFallbackLaunchesForTesting(
          const <String, String>{},
          fileExists: (path) => path == '/bin/zsh',
        );
        expect(launches, hasLength(1));
        final fallback = launches.single;
        expect(fallback.shell, '/bin/zsh');
        expect(fallback.arguments, <String>['-i']);

        // The gap this closes: without the flag the effective fallback is a
        // clean `zsh -f`; the resolved shell must instead become a login shell.
        final asLogin = launchAsLoginShellForTesting(fallback);
        expect(asLogin.arguments, <String>['-l', '-i']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('present SHELL leaves the fallback empty (userShell covers it)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final launches = resolvedLoginShellFallbackLaunchesForTesting(
          const <String, String>{'SHELL': '/bin/zsh'},
          fileExists: (_) => true,
        );
        expect(launches, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('missing SHELL prefers zsh but falls back to bash then sh', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final bash = resolvedLoginShellFallbackLaunchesForTesting(
          const <String, String>{},
          fileExists: (path) => path == '/bin/bash' || path == '/bin/sh',
        );
        expect(bash.single.shell, '/bin/bash');

        final none = resolvedLoginShellFallbackLaunchesForTesting(
          const <String, String>{},
          fileExists: (_) => false,
        );
        expect(none, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('login shell setting resolves to a macOS-only default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(TerminalSettings.defaults.resolvedLoginShell, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(TerminalSettings.defaults.resolvedLoginShell, isFalse);
        expect(
          TerminalSettings.defaults
              .copyWith(loginShell: true)
              .resolvedLoginShell,
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
