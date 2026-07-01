part of 'terminal_shell_startup_preparer_test.dart';

void _registerTerminalShellStartupPreparerAdvancedTests() {
  test('nushell uses a managed config hook to restore Codex home', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/usr/local/bin/nu',
        arguments: const <String>['-i'],
        environment: const <String, String>{
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
      ),
    );

    final expectedConfig = p.join(
      tempDir.path,
      'terminal-shell-startup',
      'nushell',
      'config.nu',
    );
    expect(launch.arguments, hasLength(3));
    expect(launch.arguments[0], '--config');
    expect(launch.arguments[1], expectedConfig);
    expect(launch.arguments[2], '-i');
    expect(launch.setupCommand, isNull);

    final config = await File(expectedConfig).readAsString();
    expect(
      config,
      contains(
        r'let __alera_user_config = ($nu.default-config-dir | path join "config.nu")',
      ),
    );
    expect(config, contains('source \$__alera_user_config'));
    expect(config, contains(r'$env.CODEX_HOME = $env.ALERA_CODEX_HOME'));
    expect(
      config,
      contains(r'$env.CLAUDE_CONFIG_DIR = $env.ALERA_CLAUDE_CONFIG_DIR'),
    );
    expect(
      config,
      contains(r'$env.OPENCODE_CONFIG_DIR = $env.ALERA_OPENCODE_CONFIG_DIR'),
    );
    expect(
      config,
      contains(r'$env.PI_CODING_AGENT_DIR = $env.ALERA_PI_CODING_AGENT_DIR'),
    );
    expect(config, contains(r'$env.COPILOT_HOME = $env.ALERA_COPILOT_HOME'));
    expect(config, contains('ALERA_AGENT_WRAPPER_PATH'));
    expect(config, contains('pre_prompt'));
  });

  test('nushell custom-config launches keep a setup-command fallback', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/usr/local/bin/nu',
        arguments: const <String>['--config', '/Users/tester/config.nu', '-i'],
        environment: const <String, String>{
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
        setupCommand: 'print setup\n',
      ),
    );

    expect(launch.arguments, const <String>[
      '--config',
      '/Users/tester/config.nu',
      '-i',
    ]);
    expect(
      launch.setupCommand,
      startsWith(
        r'if ("ALERA_CODEX_HOME" in $env) { $env.CODEX_HOME = $env.ALERA_CODEX_HOME }'
        '\n'
        r'if ("ALERA_CLAUDE_CONFIG_DIR" in $env) { $env.CLAUDE_CONFIG_DIR = $env.ALERA_CLAUDE_CONFIG_DIR }'
        '\n'
        r'if ("ALERA_OPENCODE_CONFIG_DIR" in $env) { $env.OPENCODE_CONFIG_DIR = $env.ALERA_OPENCODE_CONFIG_DIR }'
        '\n'
        r'if ("ALERA_PI_CODING_AGENT_DIR" in $env) { $env.PI_CODING_AGENT_DIR = $env.ALERA_PI_CODING_AGENT_DIR }'
        '\n'
        r'if ("ALERA_COPILOT_HOME" in $env) { $env.COPILOT_HOME = $env.ALERA_COPILOT_HOME }'
        '\n',
      ),
    );
    expect(
      launch.setupCommand,
      contains(r'let __alera_wrapper_dirs = ($env.ALERA_AGENT_WRAPPER_PATH'),
    );
    expect(launch.setupCommand, contains('print setup\n'));
  });

  test('cmd launches keep a command-prompt setup-command fallback', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: r'C:\Windows\System32\cmd.exe',
        arguments: const <String>['/d'],
        environment: const <String, String>{
          'CODEX_HOME': r'C:\Alera\codex-home',
          'ALERA_CODEX_HOME': r'C:\Alera\codex-home',
        },
      ),
    );

    expect(launch.arguments, const <String>['/d']);
    expect(
      launch.setupCommand,
      'if defined ALERA_CODEX_HOME set "CODEX_HOME=%ALERA_CODEX_HOME%"\n'
      'if defined ALERA_CLAUDE_CONFIG_DIR set "CLAUDE_CONFIG_DIR=%ALERA_CLAUDE_CONFIG_DIR%"\n'
      'if defined ALERA_OPENCODE_CONFIG_DIR set "OPENCODE_CONFIG_DIR=%ALERA_OPENCODE_CONFIG_DIR%"\n'
      'if defined ALERA_PI_CODING_AGENT_DIR set "PI_CODING_AGENT_DIR=%ALERA_PI_CODING_AGENT_DIR%"\n'
      'if defined ALERA_COPILOT_HOME set "COPILOT_HOME=%ALERA_COPILOT_HOME%"\n'
      'if defined ALERA_AGENT_WRAPPER_PATH set "PATH=%ALERA_AGENT_WRAPPER_PATH%;%PATH%"\n',
    );
  });

  test('cmd launches prepend restore before existing setup commands', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: r'C:\Windows\System32\cmd.exe',
        environment: const <String, String>{
          'CODEX_HOME': r'C:\Alera\codex-home',
          'ALERA_CODEX_HOME': r'C:\Alera\codex-home',
        },
        setupCommand: 'echo setup\n',
      ),
    );

    expect(
      launch.setupCommand,
      'if defined ALERA_CODEX_HOME set "CODEX_HOME=%ALERA_CODEX_HOME%"\n'
      'if defined ALERA_CLAUDE_CONFIG_DIR set "CLAUDE_CONFIG_DIR=%ALERA_CLAUDE_CONFIG_DIR%"\n'
      'if defined ALERA_OPENCODE_CONFIG_DIR set "OPENCODE_CONFIG_DIR=%ALERA_OPENCODE_CONFIG_DIR%"\n'
      'if defined ALERA_PI_CODING_AGENT_DIR set "PI_CODING_AGENT_DIR=%ALERA_PI_CODING_AGENT_DIR%"\n'
      'if defined ALERA_COPILOT_HOME set "COPILOT_HOME=%ALERA_COPILOT_HOME%"\n'
      'if defined ALERA_AGENT_WRAPPER_PATH set "PATH=%ALERA_AGENT_WRAPPER_PATH%;%PATH%"\n'
      'echo setup\n',
    );
  });

  test('POSIX fallback shells keep a setup-command fallback', () async {
    for (final shell in _posixFallbackShells) {
      final launch = await preparer.prepare(
        _launch(
          shell: shell,
          arguments: const <String>['-l'],
          environment: const <String, String>{
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
          },
        ),
      );

      expect(launch.arguments, const <String>['-l']);
      expect(launch.setupCommand, _expectedPosixRestoreManagedAgentEnvironment);
    }
  });

  test(
    'POSIX fallback shells prepend restore before existing setup commands',
    () async {
      for (final shell in _posixFallbackShells) {
        final launch = await preparer.prepare(
          _launch(
            shell: shell,
            environment: const <String, String>{
              'CODEX_HOME': '/runtime/codex',
              'ALERA_CODEX_HOME': '/runtime/codex',
            },
            setupCommand: 'printf setup\n',
          ),
        );

        expect(
          launch.setupCommand,
          '${_expectedPosixRestoreManagedAgentEnvironment}printf setup\n',
        );
      }
    },
  );

  test('POSIX fallback shells preserve leading empty PATH entries', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/bin/sh',
        environment: const <String, String>{
          'ALERA_AGENT_WRAPPER_PATH': '/wrapper/bin',
        },
        setupCommand: 'printf "%s" "\$PATH"\n',
      ),
    );

    final result = await Process.run(
      '/bin/sh',
      <String>['-c', launch.setupCommand!],
      includeParentEnvironment: false,
      environment: const <String, String>{
        'ALERA_AGENT_WRAPPER_PATH': '/wrapper/bin',
        'PATH': ':/usr/bin:/wrapper/bin',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, '/wrapper/bin::/usr/bin');
  });

  test('Claude runtime env alone triggers shell restore preparation', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/bin/sh',
        arguments: const <String>['-l'],
        environment: const <String, String>{
          'CLAUDE_CONFIG_DIR': '/runtime/claude',
          'ALERA_CLAUDE_CONFIG_DIR': '/runtime/claude',
        },
      ),
    );

    expect(launch.arguments, const <String>['-l']);
    expect(
      launch.setupCommand,
      contains('export CLAUDE_CONFIG_DIR="\$ALERA_CLAUDE_CONFIG_DIR"'),
    );
  });

  test(
    'OpenCode and Pi overlay env alone triggers shell restore preparation',
    () async {
      final launch = await preparer.prepare(
        _launch(
          shell: '/bin/sh',
          arguments: const <String>['-l'],
          environment: const <String, String>{
            'OPENCODE_CONFIG_DIR': '/runtime/opencode',
            'ALERA_OPENCODE_CONFIG_DIR': '/runtime/opencode',
            'PI_CODING_AGENT_DIR': '/runtime/pi',
            'ALERA_PI_CODING_AGENT_DIR': '/runtime/pi',
          },
        ),
      );

      expect(launch.arguments, const <String>['-l']);
      expect(
        launch.setupCommand,
        contains('export OPENCODE_CONFIG_DIR="\$ALERA_OPENCODE_CONFIG_DIR"'),
      );
      expect(
        launch.setupCommand,
        contains('export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"'),
      );
    },
  );

  test(
    'Pi and wrapper env trigger restore when they are the only managed env',
    () async {
      final piLaunch = await preparer.prepare(
        _launch(
          shell: '/bin/sh',
          arguments: const <String>['-l'],
          environment: const <String, String>{
            'PI_CODING_AGENT_DIR': '/runtime/pi',
            'ALERA_PI_CODING_AGENT_DIR': '/runtime/pi',
          },
        ),
      );
      final wrapperLaunch = await preparer.prepare(
        _launch(
          shell: '/bin/sh',
          arguments: const <String>['-l'],
          environment: const <String, String>{
            'ALERA_AGENT_WRAPPER_PATH': '/runtime/wrappers',
          },
        ),
      );

      expect(
        piLaunch.setupCommand,
        contains('export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"'),
      );
      expect(wrapperLaunch.setupCommand, contains('ALERA_AGENT_WRAPPER_PATH'));
    },
  );

  test(
    'unsupported shells keep env-only launches without setup syntax',
    () async {
      for (final shell in <String>['/usr/local/bin/elvish']) {
        final launch = _launch(
          shell: shell,
          environment: const <String, String>{
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
          },
        );

        expect(await preparer.prepare(launch), same(launch));
      }
    },
  );

  test('generated zsh startup moves wrapper dir to front, not skip', () async {
    final prepared = await preparer.prepare(
      _launch(
        shell: '/bin/zsh',
        environment: const <String, String>{
          'HOME': '/Users/leynier',
          'ALERA_AGENT_WRAPPER_PATH': '/wrapper/bin',
        },
      ),
    );
    final zdotdir = prepared.environment!['ZDOTDIR']!;
    for (final fileName in const <String>['.zshenv', '.zshrc']) {
      final contents = File(p.join(zdotdir, fileName)).readAsStringSync();
      expect(
        contents,
        contains(
          r'__alera_wrapper_path=("${(@ps.:.)ALERA_AGENT_WRAPPER_PATH}")',
        ),
        reason: '$fileName must rebuild PATH with the wrapper dir first',
      );
      expect(
        contents,
        isNot(contains(r'*":${ALERA_AGENT_WRAPPER_PATH}:"*) ;;')),
        reason: '$fileName must not skip when the wrapper dir is present',
      );
    }
  });

  test('zsh startup puts wrapper dir first even after rc prepends', () async {
    final zshExecutable = <String>[
      '/bin/zsh',
      '/usr/bin/zsh',
      '/usr/local/bin/zsh',
      '/opt/homebrew/bin/zsh',
    ].firstWhere((path) => File(path).existsSync(), orElse: () => '');
    if (zshExecutable.isEmpty) {
      markTestSkipped('zsh is not available on this platform');
      return;
    }

    // A user ZDOTDIR whose .zshenv prepends a decoy dir, the exact shape that
    // defeated the previous skip-if-present logic.
    final userZdotdir = Directory(p.join(tempDir.path, 'user-zdotdir'))
      ..createSync(recursive: true);
    File(
      p.join(userZdotdir.path, '.zshenv'),
    ).writeAsStringSync('export PATH="/decoy/bin:\$PATH"\n');

    final prepared = await preparer.prepare(
      _launch(
        shell: zshExecutable,
        environment: <String, String>{
          'HOME': userZdotdir.path,
          'ZDOTDIR': userZdotdir.path,
          'ALERA_AGENT_WRAPPER_PATH': '/wrapper/bin',
        },
      ),
    );
    final managedZdotdir = prepared.environment!['ZDOTDIR']!;
    final originalZdotdir = prepared.environment!['ALERA_ORIG_ZDOTDIR']!;

    // Wrapper dir starts in the middle of PATH; the rc prepend then pushes a
    // decoy in front of it, so only "move to front" yields the right result.
    final result = await Process.run(
      zshExecutable,
      const <String>['-c', r'print -rn -- ${path[1]}'],
      includeParentEnvironment: false,
      environment: <String, String>{
        'ZDOTDIR': managedZdotdir,
        'ALERA_ORIG_ZDOTDIR': originalZdotdir,
        'ALERA_AGENT_WRAPPER_PATH': '/wrapper/bin',
        'HOME': userZdotdir.path,
        'PATH': '/usr/bin:/wrapper/bin:/bin',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect((result.stdout as String).trim(), '/wrapper/bin');
  });

  test(
    'zsh startup splits merged wrapper dirs before restoring PATH',
    () async {
      final zshExecutable = <String>[
        '/bin/zsh',
        '/usr/bin/zsh',
        '/usr/local/bin/zsh',
        '/opt/homebrew/bin/zsh',
      ].firstWhere((path) => File(path).existsSync(), orElse: () => '');
      if (zshExecutable.isEmpty) {
        markTestSkipped('zsh is not available on this platform');
        return;
      }

      final userZdotdir = Directory(p.join(tempDir.path, 'user-zdotdir-multi'))
        ..createSync(recursive: true);
      File(
        p.join(userZdotdir.path, '.zshenv'),
      ).writeAsStringSync('export PATH="/decoy/bin:\$PATH"\n');

      final prepared = await preparer.prepare(
        _launch(
          shell: zshExecutable,
          environment: <String, String>{
            'HOME': userZdotdir.path,
            'ZDOTDIR': userZdotdir.path,
            'ALERA_AGENT_WRAPPER_PATH': '/wrapper/one:/wrapper/two',
          },
        ),
      );

      final result = await Process.run(
        zshExecutable,
        const <String>['-c', r'print -rn -- ${path[1]}:${path[2]}'],
        includeParentEnvironment: false,
        environment: <String, String>{
          'ZDOTDIR': prepared.environment!['ZDOTDIR']!,
          'ALERA_ORIG_ZDOTDIR': prepared.environment!['ALERA_ORIG_ZDOTDIR']!,
          'ALERA_AGENT_WRAPPER_PATH': '/wrapper/one:/wrapper/two',
          'HOME': userZdotdir.path,
          'PATH': '/usr/bin:/wrapper/two:/bin:/wrapper/one',
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect((result.stdout as String).trim(), '/wrapper/one:/wrapper/two');
    },
  );
}
