import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AleraTerminalShellStartupPreparer', () {
    late Directory tempDir;
    late AleraTerminalShellStartupPreparer preparer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'alera-terminal-startup-test-',
      );
      preparer = AleraTerminalShellStartupPreparer(
        applicationSupportDirectory: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

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
          contains(
            'export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"',
          ),
        );
        expect(
          zshrc,
          contains(
            'export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"',
          ),
        );
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
          contains(
            'export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"',
          ),
        );
        expect(
          rcFile,
          contains(
            'export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"',
          ),
        );
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

        expect(launch.setupCommand, 'Write-Output setup\n');
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
        expect(script, contains(r'$env:CODEX_HOME = $env:ALERA_CODEX_HOME'));
        expect(
          script,
          contains(r'$env:CLAUDE_CONFIG_DIR = $env:ALERA_CLAUDE_CONFIG_DIR'),
        );
        expect(
          script,
          contains(
            r'$env:OPENCODE_CONFIG_DIR = $env:ALERA_OPENCODE_CONFIG_DIR',
          ),
        );
        expect(
          script,
          contains(
            r'$env:PI_CODING_AGENT_DIR = $env:ALERA_PI_CODING_AGENT_DIR',
          ),
        );
      },
    );

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
        'if set -q ALERA_PI_CODING_AGENT_DIR; set -gx PI_CODING_AGENT_DIR \$ALERA_PI_CODING_AGENT_DIR; end',
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
          'if set -q ALERA_PI_CODING_AGENT_DIR; set -gx PI_CODING_AGENT_DIR \$ALERA_PI_CODING_AGENT_DIR; end\n',
        ),
      );
      expect(launch.setupCommand, contains('printf setup\n'));
    });

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
      expect(config, contains('pre_prompt'));
    });

    test('nushell custom-config launches keep a setup-command fallback', () async {
      final launch = await preparer.prepare(
        _launch(
          shell: '/usr/local/bin/nu',
          arguments: const <String>[
            '--config',
            '/Users/tester/config.nu',
            '-i',
          ],
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
        'if defined ALERA_PI_CODING_AGENT_DIR set "PI_CODING_AGENT_DIR=%ALERA_PI_CODING_AGENT_DIR%"\n',
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
          'if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"; fi\n',
        );
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
            'if [ -n "\${ALERA_CODEX_HOME:-}" ]; then export CODEX_HOME="\$ALERA_CODEX_HOME"; fi\n'
            'if [ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]; then export CLAUDE_CONFIG_DIR="\$ALERA_CLAUDE_CONFIG_DIR"; fi\n'
            'if [ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]; then export OPENCODE_CONFIG_DIR="\$ALERA_OPENCODE_CONFIG_DIR"; fi\n'
            'if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"; fi\n'
            'printf setup\n',
          );
        }
      },
    );

    test(
      'Claude runtime env alone triggers shell restore preparation',
      () async {
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
      },
    );

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
  });
}

const List<String> _posixFallbackShells = <String>[
  '/bin/ash',
  '/bin/dash',
  '/bin/ksh',
  '/bin/mksh',
  '/bin/oksh',
  '/bin/sh',
];

GhosttyTerminalShellLaunch _launch({
  required String shell,
  List<String> arguments = const <String>[],
  Map<String, String> environment = const <String, String>{},
  String? setupCommand,
}) {
  return GhosttyTerminalShellLaunch(
    label: shell,
    shell: shell,
    arguments: arguments,
    environment: environment,
    setupCommand: setupCommand,
  );
}

String _decodePowerShellEncodedCommand(String encodedCommand) {
  final bytes = base64.decode(encodedCommand);
  final codeUnits = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}
