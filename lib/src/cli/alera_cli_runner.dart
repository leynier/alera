import 'dart:async';
import 'dart:io' as io;

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_entrypoint.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';

typedef TerminalHostServerRunner =
    Future<void> Function({
      required String runtimeDir,
      required String controlFilePath,
      required String token,
      required TerminalHostConfig config,
    });

Future<int> runAleraCli(
  List<String> arguments, {
  StringSink? stdout,
  StringSink? stderr,
  TerminalHostServerRunner terminalHostServerRunner =
      runAleraTerminalHostServer,
}) async {
  final output = stdout ?? io.stdout;
  final errors = stderr ?? io.stderr;
  final runner = AleraCliCommandRunner(
    stdout: output,
    terminalHostServerRunner: terminalHostServerRunner,
  );
  try {
    final exitCode = await runner.run(arguments);
    return exitCode ?? 0;
  } on UsageException catch (error) {
    errors
      ..writeln(error.message)
      ..writeln()
      ..writeln(error.usage);
    return _usageExitCode;
  }
}

final class AleraCliCommandRunner extends CommandRunner<int> {
  factory AleraCliCommandRunner({
    required StringSink stdout,
    required TerminalHostServerRunner terminalHostServerRunner,
  }) {
    return AleraCliCommandRunner._(stdout, terminalHostServerRunner);
  }

  AleraCliCommandRunner._(
    this._stdout,
    TerminalHostServerRunner terminalHostServerRunner,
  ) : super('alera', 'Alera command line tools.') {
    addCommand(
      AleraTerminalHostCommand(
        stdout: _stdout,
        terminalHostServerRunner: terminalHostServerRunner,
      ),
    );
  }

  final StringSink _stdout;

  @override
  Future<int?> runCommand(ArgResults topLevelResults) {
    if (topLevelResults.flag('help')) {
      printUsage();
      return Future<int?>.value(0);
    }
    if (topLevelResults.command == null && topLevelResults.rest.isEmpty) {
      usageException('Missing command.');
    }
    return super.runCommand(topLevelResults);
  }

  @override
  void printUsage() {
    _stdout.writeln(usage);
  }
}

final class AleraTerminalHostCommand extends Command<int> {
  factory AleraTerminalHostCommand({
    required StringSink stdout,
    required TerminalHostServerRunner terminalHostServerRunner,
  }) {
    return AleraTerminalHostCommand._(stdout, terminalHostServerRunner);
  }

  AleraTerminalHostCommand._(this._stdout, this._terminalHostServerRunner) {
    argParser
      ..addOption(
        'runtime-dir',
        valueHelp: 'path',
        help: 'Directory used for host control and terminal checkpoints.',
      )
      ..addOption(
        'control-file',
        valueHelp: 'path',
        help: 'JSON file where the host publishes its socket metadata.',
      )
      ..addOption(
        'token',
        valueHelp: 'token',
        help: 'Shared authentication token expected by the host.',
      )
      ..addOption(
        'empty-shutdown-delay-seconds',
        valueHelp: 'seconds',
        defaultsTo: defaultTerminalHostEmptyShutdownDelaySeconds.toString(),
        help: 'Seconds to keep an empty host alive after the app disconnects.',
      )
      ..addOption(
        'detached-session-shutdown-delay-seconds',
        valueHelp: 'seconds',
        defaultsTo: defaultTerminalHostDetachedSessionShutdownDelaySeconds
            .toString(),
        help:
            'Seconds to keep detached running terminal sessions alive after '
            'the app disconnects.',
      )
      ..addOption(
        'scrollback-bytes',
        valueHelp: 'bytes',
        defaultsTo: defaultTerminalHostScrollbackBytes.toString(),
        help: 'Maximum host-side output bytes retained per terminal session.',
      );
  }

  final StringSink _stdout;
  final TerminalHostServerRunner _terminalHostServerRunner;

  @override
  String get name => aleraTerminalHostCommand;

  @override
  String get description => 'Run the persistent terminal host sidecar.';

  @override
  bool get takesArguments => false;

  @override
  Future<int> run() async {
    final runtimeDir = _requiredOption('runtime-dir');
    final controlFilePath = _requiredOption('control-file');
    final token = _requiredOption('token');
    final config = TerminalHostConfig(
      emptyShutdownDelaySeconds: _positiveIntOption(
        'empty-shutdown-delay-seconds',
      ),
      detachedSessionShutdownDelaySeconds: _positiveIntOption(
        'detached-session-shutdown-delay-seconds',
      ),
      scrollbackBytes: _positiveIntOption('scrollback-bytes'),
    );
    await _terminalHostServerRunner(
      runtimeDir: runtimeDir,
      controlFilePath: controlFilePath,
      token: token,
      config: config,
    );
    return 0;
  }

  @override
  void printUsage() {
    _stdout.writeln(usage);
  }

  String _requiredOption(String name) {
    final value = argResults?.option(name)?.trim();
    if (value == null || value.isEmpty) {
      usageException('Missing required option --$name.');
    }
    return value;
  }

  int _positiveIntOption(String name) {
    final value = int.tryParse(_requiredOption(name));
    if (value == null || value <= 0) {
      usageException('--$name must be a positive integer.');
    }
    return value;
  }
}

const int _usageExitCode = 64;
