part of 'alera_debug.dart';

final class _DebugContext {
  _DebugContext(this._options);

  final _Options _options;

  // Builds the Rust sidecar (rust/alera-cli) and stages its runtime bundle so
  // ALERA_CLI_BUNDLE_DIR resolution finds every required asset.
  Future<int> buildCli({String? outputDir, bool release = true}) async {
    final cargoExit = await _run(_options.cargoExecutable, <String>[
      'build',
      '--locked',
      '-p',
      'alera-cli',
      if (release) '--release',
    ], workingDirectory: _rustDir);
    if (cargoExit != 0) {
      return cargoExit;
    }
    return _stageCliBinary(
      outputDir ?? _options.bundleDir,
      profile: release ? 'release' : 'debug',
    );
  }

  Future<int> buildRuntimeDev() => buildCli(release: false);

  Future<int> _stageCliBinary(
    String outputDir, {
    required String profile,
  }) async {
    final source = File(_join(_rustDir, 'target', profile, _cliExecutableName));
    if (!await source.exists()) {
      stderr.writeln('Built Alera CLI binary not found at ${source.path}.');
      return 1;
    }
    final destinationDir = Directory(_absoluteBuildOutputPath(outputDir));
    await destinationDir.create(recursive: true);
    final helperExit = await _prepareCliNativeHelpers(destinationDir);
    if (helperExit != 0) {
      return helperExit;
    }
    final destination = File(_join(destinationDir.path, _cliExecutableName));
    final staged = File(
      '${destination.path}.stage-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await source.copy(staged.path);
      if (!Platform.isWindows) {
        await _run('chmod', <String>['755', staged.path]);
      } else if (await destination.exists()) {
        await destination.delete();
      }
      await staged.rename(destination.path);
    } finally {
      if (await staged.exists()) {
        await staged.delete();
      }
    }
    return 0;
  }

  Future<int> _prepareCliNativeHelpers(Directory destinationDir) {
    return _run(Platform.resolvedExecutable, <String>[
      'tool/native_helpers/prepare_native_helpers.dart',
      '--platform',
      Platform.operatingSystem,
      '--output',
      _join(destinationDir.path, 'emulator'),
    ]);
  }

  Future<int> cliHelp() async {
    final buildExit = await buildCli();
    if (buildExit != 0) {
      return buildExit;
    }
    return _run(_cliExecutablePath, const <String>['--help']);
  }

  // Runs the compiled Rust sidecar in the foreground for stdout/stderr debugging.
  Future<int> hostDebugForeground() async {
    final buildExit = await buildCli();
    if (buildExit != 0) {
      return buildExit;
    }
    final paths = _runtimePaths;
    await paths.runtimeDir.create(recursive: true);
    if (await paths.controlFile.exists()) {
      await paths.controlFile.delete();
    }
    return _run(_cliExecutablePath, <String>[
      'runtime-host',
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
    ], forwardStdin: true);
  }

  Future<int> appDebug() async {
    await _prepareFlavor();
    return _run(
      _options.flutterExecutable,
      _flutterRunArguments(),
      environment: _flutterEnvironment(),
      forwardStdin: true,
    );
  }

  Future<int> appProfile() async {
    await _prepareFlavor();
    return _run(
      _options.flutterExecutable,
      _flutterRunArguments(profile: true),
      environment: _flutterEnvironment(),
      forwardStdin: true,
    );
  }

  Future<int> appDebugBundledCli() async {
    await _prepareFlavor();
    final buildOutputDir = await _appDebugBundledCliOutputDir();
    final buildExit = await buildCli(outputDir: buildOutputDir);
    if (buildExit != 0) {
      return buildExit;
    }
    final environment = _flutterEnvironment();
    environment['ALERA_CLI_BUNDLE_DIR'] = _cliBundlePathFor(buildOutputDir);
    return _run(
      _options.flutterExecutable,
      _flutterRunArguments(),
      environment: environment,
      forwardStdin: true,
    );
  }

  Future<int> appDebugRuntimeDev() async {
    if (_options.flavor != kAleraDevFlavor) {
      stderr.writeln(
        'The dev runtime can only be launched with the dev flavor.',
      );
      return 64;
    }
    await _prepareFlavor();
    final buildOutputDir = await _appDebugBundledCliOutputDir();
    final buildExit = await buildCli(outputDir: buildOutputDir, release: false);
    if (buildExit != 0) {
      return buildExit;
    }
    final environment = _flutterEnvironment();
    environment['ALERA_CLI_BUNDLE_DIR'] = _cliBundlePathFor(buildOutputDir);
    return _run(
      _options.flutterExecutable,
      _flutterRunArguments(),
      environment: environment,
      forwardStdin: true,
    );
  }

  Future<String> _appDebugBundledCliOutputDir() async {
    if (!Platform.isWindows) {
      return _options.bundleDir;
    }

    final fixedBundleHosts = (await _listProcesses())
        .where(_isCliBundleTerminalHostProcess)
        .toList(growable: false);
    if (fixedBundleHosts.isEmpty) {
      return _options.bundleDir;
    }

    final outputDir = _windowsSideBySideCliBuildOutputPath();
    stdout.writeln(
      'Bundled runtime host is still running from ${_options.bundleDir}; '
      'building a fresh Windows bundle at $outputDir.',
    );
    return outputDir;
  }

  bool _isCliBundleTerminalHostProcess(_ProcessInfo process) {
    final commandLine = _normalizeProcessText(process.commandLine);
    return (commandLine.contains('runtime-host') ||
            commandLine.contains('terminal-host')) &&
        _containsNormalizedPathRoot(
          commandLine,
          _normalizeProcessText(_cliBuildOutputPath),
        );
  }

  List<String> _flutterRunArguments({bool profile = false}) {
    return <String>[
      'run',
      '-d',
      _options.device,
      if (profile) '--profile',
      '--dart-define=ALERA_FLAVOR=${_options.flavor}',
      if (profile) '--dart-define=ALERA_PERF_TRACE=true',
    ];
  }

  Map<String, String> _flutterEnvironment() {
    final environment = Map<String, String>.of(Platform.environment);
    environment['ALERA_FLAVOR'] = _options.flavor;
    return environment;
  }

  Future<void> _prepareFlavor() async {
    if (!Platform.isMacOS) {
      return;
    }
    final configFile = File(
      _join(_repoRoot, 'macos', 'Runner', 'Configs', 'Flavor.xcconfig'),
    );
    final isRelease = _options.flavor == kAleraReleaseFlavor;
    final productName = isRelease ? kAleraReleaseAppName : kAleraDevAppName;
    final bundleId = isRelease ? kAleraReleaseBundleId : kAleraDevBundleId;
    final contents = <String>[
      '// Generated by tool/debug/alera_debug.dart for ALERA_FLAVOR=${_options.flavor}.',
      '// Do not edit by hand; regenerated on every build that goes through the makefile.',
      'ALERA_PRODUCT_NAME = $productName',
      'ALERA_BUNDLE_ID = $bundleId',
      '',
    ].join('\n');
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(contents);
  }

  Future<int> debugProcesses() async {
    final processes = await _listProcesses();
    final matches = processes.where(_isAleraProcess).toList();
    if (matches.isEmpty) {
      stdout.writeln('No Alera app or runtime-host processes found.');
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
        'No runtime host control file found at ${controlFile.path}.',
      );
      return 0;
    }
    final decoded = jsonDecode(await controlFile.readAsString());
    if (decoded is! Map || decoded['pid'] is! int) {
      stderr.writeln('Runtime host control file does not contain a pid.');
      return 1;
    }
    final pid = decoded['pid'] as int;
    final stopped = Process.killPid(pid);
    await controlFile.delete();
    stdout.writeln(
      stopped
          ? 'Stopped runtime host pid $pid and removed ${controlFile.path}.'
          : 'Runtime host pid $pid was not running; removed stale ${controlFile.path}.',
    );
    return 0;
  }

  bool _isAleraProcess(_ProcessInfo process) {
    final commandLine = process.commandLine;
    final normalized = _normalizeSeparators(commandLine);
    return commandLine.contains('alera runtime-host') ||
        commandLine.contains('alera terminal-host') ||
        normalized.contains('/alera/alera') ||
        normalized.contains('/.dart_tool/alera/alera') ||
        normalized.contains('/Alera.app/Contents/MacOS/Alera') ||
        normalized.contains('/Alera Dev.app/Contents/MacOS/Alera Dev') ||
        normalized.contains('/alera-dev') ||
        normalized.endsWith('alera-dev') ||
        normalized.endsWith('alera-dev.exe');
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

  String get _rustDir => _join(_repoRoot, 'rust');

  String get _cliExecutableName => Platform.isWindows ? 'alera.exe' : 'alera';

  String get _cliExecutablePath {
    return _join(_cliBundlePathFor(_options.bundleDir), _cliExecutableName);
  }

  // The Rust sidecar and its `emulator` assets are staged directly in the
  // bundle dir, so ALERA_CLI_BUNDLE_DIR points at the directory holding both.
  String _cliBundlePathFor(String buildOutputDir) {
    return _absoluteBuildOutputPath(buildOutputDir);
  }

  String get _cliBuildOutputPath {
    return _absoluteBuildOutputPath(_options.bundleDir);
  }

  String _absoluteBuildOutputPath(String buildOutputDir) {
    final bundleDir = Directory(buildOutputDir);
    return bundleDir.isAbsolute
        ? bundleDir.path
        : _join(_repoRoot, bundleDir.path);
  }

  String _windowsSideBySideCliBuildOutputPath() {
    final absoluteOutput = _cliBuildOutputPath;
    final outputName = _pathBasename(absoluteOutput);
    final runsRoot = _join(
      Directory(absoluteOutput).parent.path,
      '$outputName-runs',
    );
    return _join(
      runsRoot,
      'app-debug-${DateTime.now().toUtc().millisecondsSinceEpoch}',
    );
  }

  String _pathBasename(String path) {
    final normalized = _normalizeSeparators(
      path,
    ).replaceAll(RegExp(r'/+$'), '');
    final separator = normalized.lastIndexOf('/');
    if (separator < 0) {
      return normalized;
    }
    return normalized.substring(separator + 1);
  }
}
