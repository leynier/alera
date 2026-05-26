import 'package:alera/src/cli/alera_cli_runner.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prints top-level help without starting the terminal host', () async {
    final stdout = StringBuffer();

    final exitCode = await runAleraCli(
      const <String>['--help'],
      stdout: stdout,
      terminalHostServerRunner: _unexpectedTerminalHostRunner,
    );

    expect(exitCode, 0);
    expect(stdout.toString(), contains('Alera command line tools.'));
    expect(stdout.toString(), contains('terminal-host'));
  });

  test('returns usage errors for missing and unknown commands', () async {
    final missingStderr = StringBuffer();
    final missingExitCode = await runAleraCli(
      const <String>[],
      stderr: missingStderr,
      terminalHostServerRunner: _unexpectedTerminalHostRunner,
    );

    final unknownStderr = StringBuffer();
    final unknownExitCode = await runAleraCli(
      const <String>['bogus'],
      stderr: unknownStderr,
      terminalHostServerRunner: _unexpectedTerminalHostRunner,
    );

    expect(missingExitCode, 64);
    expect(missingStderr.toString(), contains('Missing command.'));
    expect(unknownExitCode, 64);
    expect(unknownStderr.toString(), contains('Could not find a command'));
  });

  test('prints terminal-host command help', () async {
    final stdout = StringBuffer();

    final exitCode = await runAleraCli(
      const <String>['terminal-host', '--help'],
      stdout: stdout,
      terminalHostServerRunner: _unexpectedTerminalHostRunner,
    );

    expect(exitCode, 0);
    expect(stdout.toString(), contains('Run the persistent terminal host'));
    expect(stdout.toString(), contains('--runtime-dir'));
    expect(stdout.toString(), contains('--scrollback-bytes'));
  });

  test('validates terminal-host options', () async {
    final stderr = StringBuffer();

    final exitCode = await runAleraCli(
      const <String>['terminal-host', '--runtime-dir', '/tmp/runtime'],
      stderr: stderr,
      terminalHostServerRunner: _unexpectedTerminalHostRunner,
    );

    expect(exitCode, 64);
    expect(
      stderr.toString(),
      contains('Missing required option --control-file'),
    );
  });

  test('runs terminal-host with parsed options', () async {
    final calls = <Map<String, Object>>[];

    final exitCode = await runAleraCli(
      const <String>[
        'terminal-host',
        '--runtime-dir',
        '/tmp/runtime',
        '--control-file',
        '/tmp/runtime/host.json',
        '--token',
        'token-1',
        '--empty-shutdown-delay-seconds',
        '5',
        '--detached-session-shutdown-delay-seconds',
        '10',
        '--scrollback-bytes',
        '1024',
      ],
      terminalHostServerRunner:
          ({
            required runtimeDir,
            required controlFilePath,
            required token,
            required config,
          }) async {
            calls.add(<String, Object>{
              'runtimeDir': runtimeDir,
              'controlFilePath': controlFilePath,
              'token': token,
              'config': config,
            });
          },
    );

    expect(exitCode, 0);
    expect(calls, hasLength(1));
    expect(calls.single['runtimeDir'], '/tmp/runtime');
    expect(calls.single['controlFilePath'], '/tmp/runtime/host.json');
    expect(calls.single['token'], 'token-1');
    expect(
      calls.single['config'],
      isA<TerminalHostConfig>()
          .having((config) => config.emptyShutdownDelaySeconds, 'empty', 5)
          .having(
            (config) => config.detachedSessionShutdownDelaySeconds,
            'detached',
            10,
          )
          .having((config) => config.scrollbackBytes, 'scrollback', 1024),
    );
  });

  test('runs terminal-host with default host config options', () async {
    TerminalHostConfig? capturedConfig;

    final exitCode = await runAleraCli(
      const <String>[
        'terminal-host',
        '--runtime-dir',
        '/tmp/runtime',
        '--control-file',
        '/tmp/runtime/host.json',
        '--token',
        'token-1',
      ],
      terminalHostServerRunner:
          ({
            required runtimeDir,
            required controlFilePath,
            required token,
            required TerminalHostConfig config,
          }) async {
            capturedConfig = config;
          },
    );

    expect(exitCode, 0);
    expect(capturedConfig?.toJson(), TerminalHostConfig.defaults.toJson());
  });

  test('validates positive terminal-host config options', () async {
    final stderr = StringBuffer();

    final exitCode = await runAleraCli(
      const <String>[
        'terminal-host',
        '--runtime-dir',
        '/tmp/runtime',
        '--control-file',
        '/tmp/runtime/host.json',
        '--token',
        'token-1',
        '--scrollback-bytes',
        '0',
      ],
      stderr: stderr,
      terminalHostServerRunner: _unexpectedTerminalHostRunner,
    );

    expect(exitCode, 64);
    expect(stderr.toString(), contains('--scrollback-bytes'));
  });
}

Future<void> _unexpectedTerminalHostRunner({
  required String runtimeDir,
  required String controlFilePath,
  required String token,
  required TerminalHostConfig config,
}) async {
  throw StateError('terminal host runner should not start');
}
