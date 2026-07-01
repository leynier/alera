part of 'terminal_shell_startup_preparer_test.dart';

void _registerTerminalShellStartupPreparerCoreTests() {
  test(
    'zsh uses a managed ZDOTDIR and restores managed agent env in wrappers',
    () async {
      final launch = await preparer.prepare(
        _launch(
          shell: '/bin/zsh',
          arguments: const <String>['-i'],
          environment: const <String, String>{
            'HOME': '/Users/tester',
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
          },
          setupCommand: 'printf setup\n',
        ),
      );

      final expectedZdotdir = p.join(
        tempDir.path,
        'terminal-shell-startup',
        'zsh',
      );
      expect(launch.shell, '/bin/zsh');
      expect(launch.arguments, const <String>['-i']);
      expect(launch.setupCommand, 'printf setup\n');
      expect(launch.environment, containsPair('ZDOTDIR', expectedZdotdir));
      expect(
        launch.environment,
        containsPair('ALERA_ORIG_ZDOTDIR', '/Users/tester'),
      );

      final zshenv = await File(
        p.join(expectedZdotdir, '.zshenv'),
      ).readAsString();
      expect(zshenv, contains('unset ZDOTDIR'));
      expect(zshenv, contains('source "\$_alera_user_zdotdir/.zshenv"'));
      expect(
        zshenv,
        contains(
          'export ALERA_ORIG_ZDOTDIR="\${ZDOTDIR:-\${_alera_spawn_orig_zdotdir:-\${HOME:-}}}"',
        ),
      );
      expect(zshenv, contains("export ZDOTDIR='$expectedZdotdir'"));

      final zshrc = await File(
        p.join(expectedZdotdir, '.zshrc'),
      ).readAsString();
      expect(zshrc, contains('source "\$_alera_orig_zdotdir/.zshrc"'));
      expect(zshrc, contains('export CODEX_HOME="\${ALERA_CODEX_HOME}"'));
      expect(
        zshrc,
        contains('export CLAUDE_CONFIG_DIR="\${ALERA_CLAUDE_CONFIG_DIR}"'),
      );
      expect(
        zshrc,
        contains('export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"'),
      );
      expect(
        zshrc,
        contains('export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"'),
      );
      expect(zshrc, contains('export COPILOT_HOME="\${ALERA_COPILOT_HOME}"'));
      expect(zshrc, contains('ALERA_AGENT_WRAPPER_PATH'));
      expect(zshrc, contains("export ZDOTDIR='$expectedZdotdir'"));
    },
  );

  test(
    'zsh preserves an inherited user ZDOTDIR as the original config root',
    () async {
      final launch = await preparer.prepare(
        _launch(
          shell: '/bin/zsh',
          environment: const <String, String>{
            'HOME': '/Users/tester',
            'ZDOTDIR': '/Users/tester/.config/zsh',
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
          },
        ),
      );

      final expectedZdotdir = p.join(
        tempDir.path,
        'terminal-shell-startup',
        'zsh',
      );
      expect(launch.environment, containsPair('ZDOTDIR', expectedZdotdir));
      expect(
        launch.environment,
        containsPair('ALERA_ORIG_ZDOTDIR', '/Users/tester/.config/zsh'),
      );
    },
  );

  test('zsh removes stale original config when no home is available', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/bin/zsh',
        environment: const <String, String>{
          'HOME': '',
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
      ),
    );

    expect(launch.environment, isNot(contains('ALERA_ORIG_ZDOTDIR')));
  });

  test('zsh rejects generated wrapper ZDOTDIR self-loops', () async {
    final wrapperZdotdir = p.join(
      tempDir.path,
      'terminal-shell-startup',
      'zsh',
    );
    final launch = await preparer.prepare(
      _launch(
        shell: '/bin/zsh',
        environment: <String, String>{
          'HOME': '/Users/tester',
          'ZDOTDIR': '$wrapperZdotdir/',
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
      ),
    );

    expect(launch.environment, containsPair('ZDOTDIR', wrapperZdotdir));
    expect(
      launch.environment,
      containsPair('ALERA_ORIG_ZDOTDIR', '/Users/tester'),
    );

    final repeated = await preparer.prepare(
      _launch(
        shell: '/bin/zsh',
        environment: <String, String>{
          'HOME': '/Users/tester',
          'ZDOTDIR': '$wrapperZdotdir/',
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
      ),
    );
    expect(repeated.environment, containsPair('ZDOTDIR', wrapperZdotdir));
  });

  test(
    'bash uses a managed rcfile and restores managed agent env after user rc',
    () async {
      final launch = await preparer.prepare(
        _launch(
          shell: '/usr/bin/bash',
          arguments: const <String>['-i'],
          environment: const <String, String>{
            'HOME': '/home/tester',
            'CODEX_HOME': '/runtime/codex',
            'ALERA_CODEX_HOME': '/runtime/codex',
          },
        ),
      );

      final expectedRcFile = p.join(
        tempDir.path,
        'terminal-shell-startup',
        'bash',
        'rcfile',
      );
      expect(launch.arguments, hasLength(3));
      expect(launch.arguments.first, '--rcfile');
      expect(launch.arguments[1], expectedRcFile);
      expect(launch.arguments[2], '-i');
      expect(
        launch.environment,
        containsPair('ALERA_ORIG_BASHRC', p.join('/home/tester', '.bashrc')),
      );

      final rcFile = await File(expectedRcFile).readAsString();
      expect(rcFile, contains('. "\${ALERA_ORIG_BASHRC}"'));
      expect(rcFile, contains('export CODEX_HOME="\${ALERA_CODEX_HOME}"'));
      expect(
        rcFile,
        contains('export CLAUDE_CONFIG_DIR="\${ALERA_CLAUDE_CONFIG_DIR}"'),
      );
      expect(
        rcFile,
        contains('export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"'),
      );
      expect(
        rcFile,
        contains('export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"'),
      );
      expect(rcFile, contains('export COPILOT_HOME="\${ALERA_COPILOT_HOME}"'));
      expect(rcFile, contains('__alera_appended=0'));
      expect(rcFile, contains('export PATH="\${ALERA_AGENT_WRAPPER_PATH}:'));
      expect(rcFile, isNot(contains('*":\${ALERA_AGENT_WRAPPER_PATH}:"*) ;;')));
    },
  );

  test(
    'powershell uses encoded startup restore instead of setup command',
    () async {
      final launch = await preparer.prepare(
        _launch(
          shell: r'C:\Program Files\PowerShell\7\pwsh.exe',
          arguments: const <String>['-NoLogo'],
          environment: const <String, String>{
            'CODEX_HOME': r'C:\Alera\codex-home',
            'ALERA_CODEX_HOME': r'C:\Alera\codex-home',
          },
          setupCommand: 'Write-Output setup\n',
        ),
      );

      expect(launch.setupCommand, isNull);
      expect(
        launch.arguments,
        containsAllInOrder(<String>['-NoLogo', '-NoExit', '-EncodedCommand']),
      );
      expect(
        launch.arguments.where((argument) => argument == '-NoLogo'),
        hasLength(1),
      );

      final encodedCommand =
          launch.arguments[launch.arguments.indexOf('-EncodedCommand') + 1];
      final script = _decodePowerShellEncodedCommand(encodedCommand);
      expect(script, contains('Write-Output setup\n'));
      expect(script, contains(r'$env:CODEX_HOME = $env:ALERA_CODEX_HOME'));
      expect(
        script,
        contains(r'$env:CLAUDE_CONFIG_DIR = $env:ALERA_CLAUDE_CONFIG_DIR'),
      );
      expect(
        script,
        contains(r'$env:OPENCODE_CONFIG_DIR = $env:ALERA_OPENCODE_CONFIG_DIR'),
      );
      expect(
        script,
        contains(r'$env:PI_CODING_AGENT_DIR = $env:ALERA_PI_CODING_AGENT_DIR'),
      );
      expect(script, contains(r'$env:COPILOT_HOME = $env:ALERA_COPILOT_HOME'));
      expect(script, contains(r'$env:ALERA_AGENT_WRAPPER_PATH'));
    },
  );

  test(
    'powershell encodes setup commands without managed environment',
    () async {
      final launch = await preparer.prepare(
        _launch(
          shell: r'C:\Program Files\PowerShell\7\pwsh.exe',
          setupCommand:
              "Set-Location -LiteralPath 'C:\\Users\\O''Brien\\Project'\r\n",
        ),
      );

      expect(launch.setupCommand, isNull);
      expect(
        launch.arguments,
        containsAllInOrder(<String>['-NoLogo', '-NoExit', '-EncodedCommand']),
      );
      final encodedCommand =
          launch.arguments[launch.arguments.indexOf('-EncodedCommand') + 1];
      final script = _decodePowerShellEncodedCommand(encodedCommand);
      expect(
        script,
        "Set-Location -LiteralPath 'C:\\Users\\O''Brien\\Project'\r\n",
      );
    },
  );

  test('powershell preserves existing no-logo and no-exit switches', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: r'C:\Program Files\PowerShell\7\pwsh.exe',
        arguments: const <String>['-nologo', '-noexit'],
        environment: const <String, String>{
          'CODEX_HOME': r'C:\Alera\codex-home',
          'ALERA_CODEX_HOME': r'C:\Alera\codex-home',
        },
      ),
    );

    expect(
      launch.arguments.where((argument) => argument.toLowerCase() == '-nologo'),
      hasLength(1),
    );
    expect(
      launch.arguments.where((argument) => argument.toLowerCase() == '-noexit'),
      hasLength(1),
    );
    expect(launch.arguments, contains('-EncodedCommand'));
  });

  test('fish uses an init command to restore Codex home after startup', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/opt/homebrew/bin/fish',
        arguments: const <String>['-i'],
        environment: const <String, String>{
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
      ),
    );

    expect(launch.arguments, hasLength(3));
    expect(launch.arguments[0], '-i');
    expect(launch.arguments[1], '-C');
    expect(
      launch.arguments[2],
      'if set -q ALERA_CODEX_HOME; set -gx CODEX_HOME \$ALERA_CODEX_HOME; end\n'
      'if set -q ALERA_CLAUDE_CONFIG_DIR; set -gx CLAUDE_CONFIG_DIR \$ALERA_CLAUDE_CONFIG_DIR; end\n'
      'if set -q ALERA_OPENCODE_CONFIG_DIR; set -gx OPENCODE_CONFIG_DIR \$ALERA_OPENCODE_CONFIG_DIR; end\n'
      'if set -q ALERA_PI_CODING_AGENT_DIR; set -gx PI_CODING_AGENT_DIR \$ALERA_PI_CODING_AGENT_DIR; end\n'
      'if set -q ALERA_COPILOT_HOME; set -gx COPILOT_HOME \$ALERA_COPILOT_HOME; end\n'
      'if set -q ALERA_AGENT_WRAPPER_PATH; set -l __alera_wrappers (string split : -- \$ALERA_AGENT_WRAPPER_PATH); for __alera_wrapper in \$__alera_wrappers; set PATH (string match --invert -- \$__alera_wrapper \$PATH); end; set -gx PATH \$__alera_wrappers \$PATH; end',
    );
    expect(launch.setupCommand, isNull);
  });

  test('fish command launches keep a setup-command fallback', () async {
    final launch = await preparer.prepare(
      _launch(
        shell: '/opt/homebrew/bin/fish',
        arguments: const <String>['-c', 'echo hi'],
        environment: const <String, String>{
          'CODEX_HOME': '/runtime/codex',
          'ALERA_CODEX_HOME': '/runtime/codex',
        },
        setupCommand: 'printf setup\n',
      ),
    );

    expect(launch.arguments, const <String>['-c', 'echo hi']);
    expect(
      launch.setupCommand,
      startsWith(
        'if set -q ALERA_CODEX_HOME; set -gx CODEX_HOME \$ALERA_CODEX_HOME; end\n'
        'if set -q ALERA_CLAUDE_CONFIG_DIR; set -gx CLAUDE_CONFIG_DIR \$ALERA_CLAUDE_CONFIG_DIR; end\n'
        'if set -q ALERA_OPENCODE_CONFIG_DIR; set -gx OPENCODE_CONFIG_DIR \$ALERA_OPENCODE_CONFIG_DIR; end\n'
        'if set -q ALERA_PI_CODING_AGENT_DIR; set -gx PI_CODING_AGENT_DIR \$ALERA_PI_CODING_AGENT_DIR; end\n'
        'if set -q ALERA_COPILOT_HOME; set -gx COPILOT_HOME \$ALERA_COPILOT_HOME; end\n'
        'if set -q ALERA_AGENT_WRAPPER_PATH; set -l __alera_wrappers (string split : -- \$ALERA_AGENT_WRAPPER_PATH); for __alera_wrapper in \$__alera_wrappers; set PATH (string match --invert -- \$__alera_wrapper \$PATH); end; set -gx PATH \$__alera_wrappers \$PATH; end\n',
      ),
    );
    expect(launch.setupCommand, contains('printf setup\n'));
  });
}
