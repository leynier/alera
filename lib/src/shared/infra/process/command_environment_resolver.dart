import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';

const String shellPathHydrationDelimiter = '__ALERA_SHELL_PATH__';
const String shellVariableHydrationDelimiter = '__ALERA_SHELL_VAR__';
const Duration shellPathHydrationTimeout = Duration(seconds: 5);

typedef ShellPathHydrator = Future<CommandEnvironmentHydrationResult> Function(
  String shell,
);

typedef ShellVariablesHydrator = Future<Map<String, String>> Function(
  String shell,
  List<String> names,
);

enum CommandEnvironmentHydrationFailureReason {
  none,
  noShell,
  spawnError,
  timeout,
  emptyPath,
}

class CommandEnvironmentHydrationResult {
  const CommandEnvironmentHydrationResult._({
    required this.ok,
    required this.segments,
    required this.failureReason,
  });

  const CommandEnvironmentHydrationResult.success(List<String> segments)
    : this._(
        ok: true,
        segments: segments,
        failureReason: CommandEnvironmentHydrationFailureReason.none,
      );

  const CommandEnvironmentHydrationResult.failure(
    CommandEnvironmentHydrationFailureReason failureReason,
  ) : this._(
        ok: false,
        segments: const <String>[],
        failureReason: failureReason,
      );

  final bool ok;
  final List<String> segments;
  final CommandEnvironmentHydrationFailureReason failureReason;
}

abstract interface class CommandEnvironmentResolver {
  Future<Map<String, String>> environment();

  /// Values of [names] as exported by the user's login shell (rc files
  /// included). GUI-launched processes do not inherit those exports, so this
  /// is the only way to see them. Returns an empty map on Windows, on
  /// hydration failure, or when no requested variable has a value; values are
  /// held in memory only and never persisted.
  Future<Map<String, String>> environmentVariables(List<String> names);
}

class UserCommandEnvironmentResolver implements CommandEnvironmentResolver {
  UserCommandEnvironmentResolver({
    this.platformEnvironment,
    this.isWindows,
    this.isMacOS,
    this.hydrator,
    this.variablesHydrator,
    this.processRunner = const RustProcessRunner(),
  });

  final Map<String, String>? platformEnvironment;
  final bool? isWindows;
  final bool? isMacOS;
  final ShellPathHydrator? hydrator;
  final ShellVariablesHydrator? variablesHydrator;
  final ProcessRunner processRunner;
  Future<CommandEnvironmentHydrationResult>? _hydration;
  final Map<String, Future<Map<String, String>>> _variableHydrations =
      <String, Future<Map<String, String>>>{};

  @override
  Future<Map<String, String>> environment() async {
    final base = <String, String>{
      ...(platformEnvironment ?? Platform.environment),
    };
    final result = await _hydrate();
    if (!result.ok) {
      return base;
    }
    _mergePathSegments(
      base,
      result.segments,
      isWindows: isWindows ?? Platform.isWindows,
    );
    return base;
  }

  Future<CommandEnvironmentHydrationResult> _hydrate() {
    final cached = _hydration;
    if (cached != null) {
      return cached;
    }
    final shell = _pickShell();
    if (shell == null) {
      return _hydration = Future<CommandEnvironmentHydrationResult>.value(
        const CommandEnvironmentHydrationResult.failure(
          CommandEnvironmentHydrationFailureReason.noShell,
        ),
      );
    }
    final hydrate = hydrator;
    return _hydration = hydrate != null
        ? hydrate(shell)
        : hydrateShellPath(shell, processRunner: processRunner);
  }

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) {
    final valid = names.where(isValidEnvironmentVariableName).toSet().toList()
      ..sort();
    if (valid.isEmpty) {
      return Future<Map<String, String>>.value(const <String, String>{});
    }
    final shell = _pickShell();
    if (shell == null) {
      // Windows: user/system variables already reach GUI processes, and there
      // is no login-shell rc sourcing to import from.
      return Future<Map<String, String>>.value(const <String, String>{});
    }
    final key = valid.join('\u0000');
    final hydrate = variablesHydrator;
    return _variableHydrations[key] ??= hydrate != null
        ? hydrate(shell, valid)
        : hydrateShellVariables(shell, valid, processRunner: processRunner);
  }

  String? _pickShell() {
    if (isWindows ?? Platform.isWindows) {
      return null;
    }
    final environment = platformEnvironment ?? Platform.environment;
    final shell = environment['SHELL']?.trim();
    if (shell != null && shell.isNotEmpty) {
      return shell;
    }
    return (isMacOS ?? Platform.isMacOS) ? '/bin/zsh' : '/bin/bash';
  }
}

final RegExp _environmentVariableNamePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*$',
);

/// Guards the shell command interpolation in [hydrateShellVariables]: only
/// plain identifier names are ever spliced into the probe script.
bool isValidEnvironmentVariableName(String name) {
  return _environmentVariableNamePattern.hasMatch(name);
}

Future<Map<String, String>> hydrateShellVariables(
  String shell,
  List<String> names, {
  ProcessRunner processRunner = const RustProcessRunner(),
}) async {
  final valid = names.where(isValidEnvironmentVariableName).toList();
  if (valid.isEmpty) {
    return const <String, String>{};
  }
  final command = StringBuffer();
  for (final name in valid) {
    command
      ..write("printf '%s' '$shellVariableHydrationDelimiter'; ")
      ..write('printf \'$name=%s\' "\$$name"; ')
      ..write("printf '%s' '$shellVariableHydrationDelimiter'; ");
  }
  StartedProcess process;
  try {
    process = await processRunner.start(shell, <String>[
      '-ilc',
      command.toString(),
    ]);
  } catch (_) {
    return const <String, String>{};
  }

  final stdout = StringBuffer();
  final stdoutDone = utf8.decoder.bind(process.stdout).forEach(stdout.write);
  final stderrDone = process.stderr.drain<void>();

  try {
    await process.exitCode.timeout(
      shellPathHydrationTimeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('Shell variable hydration timed out.');
      },
    );
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  } catch (_) {
    // Covers the timeout above and a spawn failure the runner reports through
    // the exit code, where `Process.start` used to throw from the call itself.
    return const <String, String>{};
  }

  return parseHydratedShellVariables(stdout.toString(), valid);
}

Map<String, String> parseHydratedShellVariables(
  String stdout,
  List<String> names,
) {
  final cleaned = stdout.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  final requested = names.toSet();
  final values = <String, String>{};
  var index = 0;
  while (true) {
    final start = cleaned.indexOf(shellVariableHydrationDelimiter, index);
    if (start < 0) {
      break;
    }
    final end = cleaned.indexOf(
      shellVariableHydrationDelimiter,
      start + shellVariableHydrationDelimiter.length,
    );
    if (end < 0) {
      break;
    }
    final chunk = cleaned.substring(
      start + shellVariableHydrationDelimiter.length,
      end,
    );
    final separator = chunk.indexOf('=');
    if (separator > 0) {
      final name = chunk.substring(0, separator).trim();
      final value = chunk.substring(separator + 1);
      if (requested.contains(name) && value.isNotEmpty) {
        values[name] = value;
      }
    }
    index = end + shellVariableHydrationDelimiter.length;
  }
  return values;
}

Future<CommandEnvironmentHydrationResult> hydrateShellPath(
  String shell, {
  ProcessRunner processRunner = const RustProcessRunner(),
}) async {
  final command =
      "printf '%s' '$shellPathHydrationDelimiter'; "
      'printf \'%s\' "\$PATH"; '
      "printf '%s' '$shellPathHydrationDelimiter'";
  StartedProcess process;
  try {
    process = await processRunner.start(shell, <String>['-ilc', command]);
  } catch (_) {
    return const CommandEnvironmentHydrationResult.failure(
      CommandEnvironmentHydrationFailureReason.spawnError,
    );
  }

  final stdout = StringBuffer();
  final stdoutDone = utf8.decoder.bind(process.stdout).forEach(stdout.write);
  final stderrDone = process.stderr.drain<void>();

  try {
    await process.exitCode.timeout(
      shellPathHydrationTimeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('Shell PATH hydration timed out.');
      },
    );
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  } on TimeoutException {
    return const CommandEnvironmentHydrationResult.failure(
      CommandEnvironmentHydrationFailureReason.timeout,
    );
  } catch (_) {
    // The runner reports a spawn that failed after `start` returned through
    // the exit code, where `Process.start` used to throw from the call itself.
    return const CommandEnvironmentHydrationResult.failure(
      CommandEnvironmentHydrationFailureReason.spawnError,
    );
  }

  final segments = parseHydratedShellPath(stdout.toString());
  if (segments.isEmpty) {
    return const CommandEnvironmentHydrationResult.failure(
      CommandEnvironmentHydrationFailureReason.emptyPath,
    );
  }
  return CommandEnvironmentHydrationResult.success(segments);
}

List<String> parseHydratedShellPath(String stdout) {
  final cleaned = stdout.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  final first = cleaned.indexOf(shellPathHydrationDelimiter);
  if (first < 0) {
    return const <String>[];
  }
  final second = cleaned.indexOf(
    shellPathHydrationDelimiter,
    first + shellPathHydrationDelimiter.length,
  );
  if (second < 0) {
    return const <String>[];
  }
  final value = cleaned
      .substring(first + shellPathHydrationDelimiter.length, second)
      .trim();
  if (value.isEmpty) {
    return const <String>[];
  }

  final seen = <String>{};
  return value
      .split(':')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty && seen.add(segment))
      .toList(growable: false);
}

List<String> mergePathSegmentsForTesting(
  Map<String, String> environment,
  List<String> segments, {
  bool? isWindows,
}) {
  return _mergePathSegments(
    environment,
    segments,
    isWindows: isWindows ?? Platform.isWindows,
  );
}

List<String> _mergePathSegments(
  Map<String, String> environment,
  List<String> segments, {
  required bool isWindows,
}) {
  if (segments.isEmpty) {
    return const <String>[];
  }
  final key = _pathEnvironmentKey(environment, isWindows: isWindows);
  final pathListSeparator = isWindows ? ';' : ':';
  final current = environment[key] ?? '';
  final existing = current
      .split(pathListSeparator)
      .where((segment) => segment.isNotEmpty)
      .toSet();
  final seenIncoming = <String>{};
  final added = segments
      .where((segment) => segment.isNotEmpty && seenIncoming.add(segment))
      .where((segment) => !existing.contains(segment))
      .toList(growable: false);
  if (added.isEmpty) {
    return const <String>[];
  }
  environment[key] = <String>[
    ...added,
    ...current.split(pathListSeparator).where((segment) => segment.isNotEmpty),
  ].join(pathListSeparator);
  return added;
}

String _pathEnvironmentKey(
  Map<String, String> environment, {
  required bool isWindows,
}) {
  if (isWindows && environment.containsKey('Path')) {
    return 'Path';
  }
  return 'PATH';
}
