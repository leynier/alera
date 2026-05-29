import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/core/build_flavor.dart';

part 'alera_debug_context.dart';
part 'alera_debug_processes.dart';
part 'alera_debug_options.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.first == 'help' ||
      arguments.first == '--help' ||
      arguments.first == '-h') {
    _printUsage();
    return;
  }

  final command = arguments.first;
  final _Options options;
  try {
    options = _Options.parse(arguments.skip(1).toList());
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
    return;
  }
  final context = _DebugContext(options);

  final result = switch (command) {
    'cli-build' => await context.buildCli(),
    'cli-help' => await context.cliHelp(),
    'host-debug' => await context.hostDebug(observe: false),
    'host-debug-observe' => await context.hostDebug(observe: true),
    'host-debug-wrapper' => await context.buildHostDebugWrapper(),
    'app-debug' => await context.appDebug(),
    'app-debug-bundled-cli' => await context.appDebugBundledCli(),
    'app-debug-host-observe' => await context.appDebugHostObserve(),
    'debug-processes' => await context.debugProcesses(),
    'host-stop' => await context.hostStop(),
    _ => _unknownCommand(command),
  };
  exitCode = result;
}

int _unknownCommand(String command) {
  stderr.writeln('Unknown debug command: $command');
  _printUsage();
  return 64;
}

void _printUsage() {
  stdout.writeln('''
Usage: dart tool/debug/alera_debug.dart <command> [options]

Commands:
  help                      List available make/debug commands.
  cli-build                 Build the bundled alera CLI sidecar.
  cli-help                  Build the sidecar and print alera --help.
  host-debug                Run alera terminal-host in the foreground.
  host-debug-observe        Run alera terminal-host with a Dart VM service.
  host-debug-wrapper        Build the app-launched VM-service wrapper.
  app-debug                 Run the Flutter desktop app.
  app-debug-bundled-cli     Run the app against the compiled CLI bundle.
  app-debug-host-observe    Run the app with a VM-service host wrapper.
  debug-processes           List likely Alera UI and host processes.
  host-stop                 Stop the current terminal host from host.json.
''');
}
