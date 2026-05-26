// ignore_for_file: prefer_initializing_formals

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
  AleraCliCommandRunner({
    required StringSink stdout,
    required TerminalHostServerRunner terminalHostServerRunner,
  }) : _stdout = stdout,
       super('alera', 'Alera command line tools.') {
    addCommand(
      AleraTerminalHostCommand(
        stdout: stdout,
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
  AleraTerminalHostCommand({
    required StringSink stdout,
    required TerminalHostServerRunner terminalHostServerRunner,
  }) : _stdout = stdout,
       _terminalHostServerRunner = terminalHostServerRunner {
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
    await _terminalHostServerRunner(
      runtimeDir: runtimeDir,
      controlFilePath: controlFilePath,
      token: token,
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
}

const int _usageExitCode = 64;
