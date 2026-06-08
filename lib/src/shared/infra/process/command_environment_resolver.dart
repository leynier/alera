import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String shellPathHydrationDelimiter = '__ALERA_SHELL_PATH__';
const Duration shellPathHydrationTimeout = Duration(seconds: 5);

typedef ShellPathHydrator =
    Future<CommandEnvironmentHydrationResult> Function(String shell);

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
}

class UserCommandEnvironmentResolver implements CommandEnvironmentResolver {
  UserCommandEnvironmentResolver({
    this.platformEnvironment,
    this.isWindows,
    this.isMacOS,
    this.hydrator,
  });

  final Map<String, String>? platformEnvironment;
  final bool? isWindows;
  final bool? isMacOS;
  final ShellPathHydrator? hydrator;
  Future<CommandEnvironmentHydrationResult>? _hydration;

  @override
  Future<Map<String, String>> environment() async {
    final base = <String, String>{
      ...(platformEnvironment ?? Platform.environment),
    };
    final result = await _hydrate();
    if (!result.ok) {
      return base;
    }
    _mergePathSegments(base, result.segments);
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
    return _hydration = (hydrator ?? hydrateShellPath)(shell);
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

Future<CommandEnvironmentHydrationResult> hydrateShellPath(String shell) async {
  final command =
      "printf '%s' '$shellPathHydrationDelimiter'; "
      'printf \'%s\' "\$PATH"; '
      "printf '%s' '$shellPathHydrationDelimiter'";
  Process process;
  try {
    process = await Process.start(shell, <String>[
      '-ilc',
      command,
    ], mode: ProcessStartMode.normal);
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
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('Shell PATH hydration timed out.');
      },
    );
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  } on TimeoutException {
    return const CommandEnvironmentHydrationResult.failure(
      CommandEnvironmentHydrationFailureReason.timeout,
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
      .split(_pathListSeparator)
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty && seen.add(segment))
      .toList(growable: false);
}

List<String> mergePathSegmentsForTesting(
  Map<String, String> environment,
  List<String> segments,
) {
  return _mergePathSegments(environment, segments);
}

List<String> _mergePathSegments(
  Map<String, String> environment,
  List<String> segments,
) {
  if (segments.isEmpty) {
    return const <String>[];
  }
  final key = _pathEnvironmentKey(environment);
  final current = environment[key] ?? '';
  final existing = current
      .split(_pathListSeparator)
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
    ...current.split(_pathListSeparator).where((segment) => segment.isNotEmpty),
  ].join(_pathListSeparator);
  return added;
}

String _pathEnvironmentKey(Map<String, String> environment) {
  if (Platform.isWindows && environment.containsKey('Path')) {
    return 'Path';
  }
  return 'PATH';
}

String get _pathListSeparator => Platform.isWindows ? ';' : ':';
