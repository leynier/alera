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
