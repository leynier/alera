part of 'terminal_shell_startup_preparer.dart';

String _encodePowerShellCommand(String script) {
  // PowerShell expects -EncodedCommand content as UTF-16LE before base64.
  final bytes = <int>[];
  for (final codeUnit in script.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return base64.encode(bytes);
}

bool _hasBashCommandArgument(List<String> arguments) {
  return arguments.any(
    (argument) => argument == '-c' || argument == '--command',
  );
}

bool _hasBashRcOverride(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    final argument = arguments[i];
    if (argument == '--rcfile' ||
        argument == '--init-file' ||
        argument.startsWith('--rcfile=') ||
        argument.startsWith('--init-file=')) {
      return true;
    }
  }
  return false;
}

bool _hasBashNoRc(List<String> arguments) {
  return arguments.any((argument) => argument == '--norc');
}

bool _hasFishCommandArgument(List<String> arguments) {
  return arguments.any((argument) {
    final lower = argument.toLowerCase();
    return lower == '-c' ||
        lower == '--command' ||
        lower.startsWith('--command=');
  });
}

bool _hasPowerShellCommandArgument(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    final argument = arguments[i].toLowerCase();
    if (argument == '-command' ||
        argument == '-c' ||
        argument == '-encodedcommand' ||
        argument == '-enc' ||
        argument == '-file') {
      return true;
    }
  }
  return false;
}

bool _isPosixSetupFallbackShell(String executable) {
  return const <String>{
    'ash',
    'dash',
    'ksh',
    'mksh',
    'oksh',
    'sh',
  }.contains(executable);
}

bool _requiresNushellSetupFallback(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    final argument = arguments[i].toLowerCase();
    if (argument == '-c' ||
        argument == '--commands' ||
        argument.startsWith('--commands=') ||
        argument == '--command' ||
        argument.startsWith('--command=') ||
        argument == '-e' ||
        argument == '--execute' ||
        argument.startsWith('--execute=')) {
      return true;
    }
    if (argument == '--config' ||
        argument.startsWith('--config=') ||
        argument == '--env-config' ||
        argument.startsWith('--env-config=') ||
        argument == '-n' ||
        argument == '--no-config-file') {
      return true;
    }
    if (!argument.startsWith('-')) {
      return true;
    }
  }
  return false;
}

bool _isPowerShellNoLogo(String argument) {
  return argument.toLowerCase() == '-nologo';
}

bool _isPowerShellNoExit(String argument) {
  return argument.toLowerCase() == '-noexit';
}

String _shellExecutableName(GhosttyTerminalShellLaunch launch) {
  final executable = launch.shell.replaceAll(r'\', '/').split('/').last;
  final lower = executable.toLowerCase();
  return lower.endsWith('.exe') ? lower.substring(0, lower.length - 4) : lower;
}
