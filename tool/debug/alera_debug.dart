import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.first == 'help' ||
      arguments.first == '--help' ||
      arguments.first == '-h') {
    _printUsage();
    return;
  }

  final command = arguments.first;
  final options = _Options.parse(arguments.skip(1).toList());
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

final class _DebugContext {
  _DebugContext(this._options);

  final _Options _options;

  Future<int> buildCli() {
    return _run(_options.dartExecutable, <String>[
      'build',
      'cli',
      '--target',
      'bin/alera.dart',
      '--output',
      _options.bundleDir,
    ]);
  }

  Future<int> cliHelp() async {
    final buildExit = await buildCli();
    if (buildExit != 0) {
      return buildExit;
    }
    return _run(_cliExecutablePath, const <String>['--help']);
  }

  Future<int> hostDebug({required bool observe}) async {
    final paths = _runtimePaths;
    await paths.runtimeDir.create(recursive: true);
    if (await paths.controlFile.exists()) {
      await paths.controlFile.delete();
    }
    final arguments = <String>[
      if (observe) '--observe=${_options.debugPort}/127.0.0.1',
      'bin/alera.dart',
      'terminal-host',
      '--runtime-dir',
      paths.runtimeDir.path,
      '--control-file',
      paths.controlFile.path,
      '--token',
      _options.debugToken,
      '--empty-shutdown-delay-seconds',
      _options.hostEmptyShutdownSeconds,
      '--detached-session-shutdown-delay-seconds',
      _options.hostDetachedShutdownSeconds,
      '--scrollback-bytes',
      _options.hostScrollbackBytes,
    ];
    return _run(_options.dartExecutable, arguments, forwardStdin: true);
  }

  Future<int> buildHostDebugWrapper() async {
    final wrapper = File(_hostDebugWrapperPath);
    await wrapper.parent.create(recursive: true);
    return _run(_options.dartExecutable, <String>[
      'compile',
      'exe',
      _join('tool', 'debug', 'alera_debug_host_wrapper.dart'),
      '-o',
      wrapper.path,
    ]);
  }

  Future<int> appDebug() {
    return _run(_options.flutterExecutable, <String>[
      'run',
      '-d',
      _options.device,
    ], forwardStdin: true);
  }

  Future<int> appDebugBundledCli() async {
    final buildExit = await buildCli();
    if (buildExit != 0) {
      return buildExit;
    }
    final environment = Map<String, String>.of(Platform.environment);
    environment['ALERA_CLI_BUNDLE_DIR'] = _join(
      _repoRoot,
      _options.bundleDir,
      'bundle',
    );
    return _run(
      _options.flutterExecutable,
      <String>['run', '-d', _options.device],
      environment: environment,
      forwardStdin: true,
    );
  }

  Future<int> appDebugHostObserve() async {
    final wrapperExit = await buildHostDebugWrapper();
    if (wrapperExit != 0) {
      return wrapperExit;
    }
    final environment = Map<String, String>.of(Platform.environment);
    environment['ALERA_CLI_PATH'] = _hostDebugWrapperPath;
    environment['ALERA_DEBUG_REPO_ROOT'] = _repoRoot;
    environment['ALERA_DEBUG_DART'] = _options.dartExecutable;
    environment['ALERA_CLI_DEBUG_PORT'] = _options.debugPort;
    return _run(
      _options.flutterExecutable,
      <String>['run', '-d', _options.device],
      environment: environment,
      forwardStdin: true,
    );
  }

  Future<int> debugProcesses() async {
    final processes = await _listProcesses();
    final matches = processes.where(_isAleraProcess).toList();
    if (matches.isEmpty) {
      stdout.writeln('No Alera app or terminal-host processes found.');
    } else {
      for (final process in matches) {
        stdout.writeln('${process.pid} ${process.commandLine}');
      }
    }

    final controlFile = _runtimePaths.controlFile;
    if (await controlFile.exists()) {
      stdout.writeln('control file: ${controlFile.path}');
      stdout.writeln(await controlFile.readAsString());
    }
    return 0;
  }

  Future<int> hostStop() async {
    final controlFile = _runtimePaths.controlFile;
    if (!await controlFile.exists()) {
      stdout.writeln(
        'No terminal host control file found at ${controlFile.path}.',
      );
      return 0;
    }
    final decoded = jsonDecode(await controlFile.readAsString());
    if (decoded is! Map || decoded['pid'] is! int) {
      stderr.writeln('Terminal host control file does not contain a pid.');
      return 1;
    }
    final pid = decoded['pid'] as int;
    final stopped = Process.killPid(pid);
    await controlFile.delete();
    stdout.writeln(
      stopped
          ? 'Stopped terminal host pid $pid and removed ${controlFile.path}.'
          : 'Terminal host pid $pid was not running; removed stale ${controlFile.path}.',
    );
    return 0;
  }

  bool _isAleraProcess(_ProcessInfo process) {
    final commandLine = process.commandLine;
    return commandLine.contains('alera terminal-host') ||
        _normalizeSeparators(commandLine).contains('/alera/bin/alera') ||
        _normalizeSeparators(
          commandLine,
        ).contains('/.dart_tool/alera/bundle/bin/alera') ||
        _normalizeSeparators(
          commandLine,
        ).contains('/Alera.app/Contents/MacOS/Alera');
  }

  _RuntimePaths get _runtimePaths {
    final supportDir =
        _options.appSupportDir ?? _defaultAppSupportDir(_options.appId);
    final runtimeDir = Directory(_join(supportDir, 'terminal_host'));
    return _RuntimePaths(
      runtimeDir: runtimeDir,
      controlFile: File(_join(runtimeDir.path, 'host.json')),
    );
  }

  String get _cliExecutablePath {
    return _join(
      _repoRoot,
      _options.bundleDir,
      'bundle',
      'bin',
      Platform.isWindows ? 'alera.exe' : 'alera',
    );
  }

  String get _hostDebugWrapperPath {
    return _join(
      _repoRoot,
      '.dart_tool',
      Platform.isWindows ? 'alera-debug-host.exe' : 'alera-debug-host',
    );
  }
}

Future<int> _run(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  bool forwardStdin = false,
}) async {
  stdout.writeln([executable, ...arguments].map(_quoteForLog).join(' '));
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: _repoRoot,
    environment: environment,
    includeParentEnvironment: true,
  );
  StreamSubscription<List<int>>? stdinSub;
  if (forwardStdin && stdin.hasTerminal) {
    stdinSub = stdin.listen(
      process.stdin.add,
      onError: process.stdin.addError,
      onDone: process.stdin.close,
    );
  }
  final stdoutDone = stdout.addStream(process.stdout);
  final stderrDone = stderr.addStream(process.stderr);
  final processExit = await process.exitCode;
  await stdinSub?.cancel();
  await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
  return processExit;
}

Future<List<_ProcessInfo>> _listProcesses() async {
  if (Platform.isWindows) {
    final executable = await _firstAvailableExecutable(<String>[
      'pwsh',
      'powershell',
    ]);
    if (executable == null) {
      stderr.writeln(
        'PowerShell 7 is required on Windows for debug-processes.',
      );
      return const <_ProcessInfo>[];
    }
    final result = await Process.run(executable, <String>[
      '-NoLogo',
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_Process | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln(result.stderr);
      return const <_ProcessInfo>[];
    }
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty) {
      return const <_ProcessInfo>[];
    }
    final decoded = jsonDecode(raw);
    final entries = decoded is List ? decoded : <Object?>[decoded];
    return entries.whereType<Map<Object?, Object?>>().map((entry) {
      return _ProcessInfo(
        pid: (entry['ProcessId'] as num).toInt(),
        commandLine: (entry['CommandLine'] as String?) ?? '',
      );
    }).toList();
  }

  final result = await Process.run('ps', const <String>[
    '-ax',
    '-o',
    'pid=,command=',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    return const <_ProcessInfo>[];
  }
  return LineSplitter.split(result.stdout as String)
      .map((line) {
        final trimmed = line.trimLeft();
        final firstSpace = trimmed.indexOf(' ');
        if (firstSpace < 0) {
          return _ProcessInfo(pid: -1, commandLine: trimmed);
        }
        return _ProcessInfo(
          pid: int.tryParse(trimmed.substring(0, firstSpace)) ?? -1,
          commandLine: trimmed.substring(firstSpace + 1).trimLeft(),
        );
      })
      .where((process) => process.pid >= 0)
      .toList();
}

Future<String?> _firstAvailableExecutable(List<String> executables) async {
  for (final executable in executables) {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      <String>[executable],
    );
    if (result.exitCode == 0) {
      return executable;
    }
  }
  return null;
}

String _defaultAppSupportDir(String appId) {
  final environment = Platform.environment;
  if (Platform.isMacOS) {
    return _join(_homeDirectory, 'Library', 'Application Support', appId);
  }
  if (Platform.isWindows) {
    final appData = environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return _join(appData, appId);
    }
  }
  final xdgDataHome = environment['XDG_DATA_HOME'];
  if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
    return _join(xdgDataHome, appId);
  }
  return _join(_homeDirectory, '.local', 'share', appId);
}

String get _homeDirectory {
  final environment = Platform.environment;
  return environment['HOME'] ??
      environment['USERPROFILE'] ??
      Directory.current.path;
}

String get _repoRoot => Directory.current.absolute.path;

String _join(
  String first,
  String second, [
  String? third,
  String? fourth,
  String? fifth,
]) {
  final parts = <String>[first, second, ?third, ?fourth, ?fifth];
  final buffer = StringBuffer(parts.first.replaceAll(RegExp(r'[/\\]+$'), ''));
  for (final part in parts.skip(1)) {
    final normalized = part
        .replaceAll(RegExp(r'^[/\\]+'), '')
        .replaceAll(RegExp(r'[/\\]+$'), '');
    if (normalized.isEmpty) {
      continue;
    }
    buffer
      ..write(Platform.pathSeparator)
      ..write(normalized);
  }
  return buffer.toString();
}

String _normalizeSeparators(String value) {
  return value.replaceAll(r'\', '/');
}

String _quoteForLog(String value) {
  if (value.contains(' ') || value.contains('\t')) {
    return '"$value"';
  }
  return value;
}

final class _Options {
  const _Options({
    required this.dartExecutable,
    required this.flutterExecutable,
    required this.device,
    required this.appId,
    required this.bundleDir,
    required this.debugPort,
    required this.debugToken,
    required this.hostEmptyShutdownSeconds,
    required this.hostDetachedShutdownSeconds,
    required this.hostScrollbackBytes,
    required this.appSupportDir,
  });

  factory _Options.parse(List<String> arguments) {
    final map = <String, String>{};
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        map[argument.substring(2, equals)] = argument.substring(equals + 1);
        continue;
      }
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for $argument');
      }
      map[argument.substring(2)] = arguments[index + 1];
      index += 1;
    }
    return _Options(
      dartExecutable: map['dart'] ?? Platform.environment['DART'] ?? 'dart',
      flutterExecutable:
          map['flutter'] ?? Platform.environment['FLUTTER'] ?? 'flutter',
      device: map['device'] ?? Platform.environment['APP_DEVICE'] ?? 'macos',
      appId:
          map['app-id'] ??
          Platform.environment['ALERA_APP_ID'] ??
          'dev.leynier.alera',
      bundleDir:
          map['bundle-dir'] ??
          Platform.environment['ALERA_CLI_BUNDLE_DIR'] ??
          '.dart_tool/alera',
      debugPort:
          map['debug-port'] ??
          Platform.environment['ALERA_CLI_DEBUG_PORT'] ??
          '8181',
      debugToken:
          map['debug-token'] ??
          Platform.environment['ALERA_CLI_DEBUG_TOKEN'] ??
          'dev-token',
      hostEmptyShutdownSeconds:
          map['host-empty-shutdown-seconds'] ??
          Platform.environment['ALERA_HOST_EMPTY_SHUTDOWN_SECONDS'] ??
          '30',
      hostDetachedShutdownSeconds:
          map['host-detached-shutdown-seconds'] ??
          Platform.environment['ALERA_HOST_DETACHED_SHUTDOWN_SECONDS'] ??
          '3600',
      hostScrollbackBytes:
          map['host-scrollback-bytes'] ??
          Platform.environment['ALERA_HOST_SCROLLBACK_BYTES'] ??
          '10000000',
      appSupportDir:
          map['app-support-dir'] ??
          Platform.environment['ALERA_APP_SUPPORT_DIR'],
    );
  }

  final String dartExecutable;
  final String flutterExecutable;
  final String device;
  final String appId;
  final String bundleDir;
  final String debugPort;
  final String debugToken;
  final String hostEmptyShutdownSeconds;
  final String hostDetachedShutdownSeconds;
  final String hostScrollbackBytes;
  final String? appSupportDir;
}

final class _RuntimePaths {
  const _RuntimePaths({required this.runtimeDir, required this.controlFile});

  final Directory runtimeDir;
  final File controlFile;
}

final class _ProcessInfo {
  const _ProcessInfo({required this.pid, required this.commandLine});

  final int pid;
  final String commandLine;
}
