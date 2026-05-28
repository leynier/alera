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
        '\n'
        r'if ("ALERA_AGENT_WRAPPER_PATH" in $env) { let __alera_path_entries = if ("PATH" in $env) { $env.PATH } else { [] }; if not ($env.ALERA_AGENT_WRAPPER_PATH in $__alera_path_entries) { $env.PATH = ($__alera_path_entries | prepend $env.ALERA_AGENT_WRAPPER_PATH) } }'
        '\n',
      ),
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
      expect(
        launch.setupCommand,
        'if [ -n "\${ALERA_CODEX_HOME:-}" ]; then export CODEX_HOME="\$ALERA_CODEX_HOME"; fi\n'
        'if [ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]; then export CLAUDE_CONFIG_DIR="\$ALERA_CLAUDE_CONFIG_DIR"; fi\n'
        'if [ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]; then export OPENCODE_CONFIG_DIR="\$ALERA_OPENCODE_CONFIG_DIR"; fi\n'
        'if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"; fi\n'
        'if [ -n "\${ALERA_COPILOT_HOME:-}" ]; then export COPILOT_HOME="\$ALERA_COPILOT_HOME"; fi\n'
        'if [ -n "\${ALERA_AGENT_WRAPPER_PATH:-}" ]; then case ":\${PATH:-}:" in *":\${ALERA_AGENT_WRAPPER_PATH}:"*) ;; *) export PATH="\${ALERA_AGENT_WRAPPER_PATH}\${PATH:+:\${PATH}}" ;; esac; fi\n',
      );
    }
  });

  test('POSIX fallback shells prepend restore before existing setup commands', () async {
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
        'if [ -n "\${ALERA_CODEX_HOME:-}" ]; then export CODEX_HOME="\$ALERA_CODEX_HOME"; fi\n'
        'if [ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]; then export CLAUDE_CONFIG_DIR="\$ALERA_CLAUDE_CONFIG_DIR"; fi\n'
        'if [ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]; then export OPENCODE_CONFIG_DIR="\$ALERA_OPENCODE_CONFIG_DIR"; fi\n'
        'if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"; fi\n'
        'if [ -n "\${ALERA_COPILOT_HOME:-}" ]; then export COPILOT_HOME="\$ALERA_COPILOT_HOME"; fi\n'
        'if [ -n "\${ALERA_AGENT_WRAPPER_PATH:-}" ]; then case ":\${PATH:-}:" in *":\${ALERA_AGENT_WRAPPER_PATH}:"*) ;; *) export PATH="\${ALERA_AGENT_WRAPPER_PATH}\${PATH:+:\${PATH}}" ;; esac; fi\n'
        'printf setup\n',
      );
    }
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
}
