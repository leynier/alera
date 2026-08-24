part of 'alera_debug.dart';

final class _DebugContext {
  _DebugContext(this._options);

  final _Options _options;

  // Builds the Rust sidecar (rust/alera-cli) in release and stages its runtime
  // bundle so ALERA_CLI_BUNDLE_DIR resolution finds every required asset.
  Future<int> buildCli({String? outputDir}) async {
    final cargoExit = await _run(_options.cargoExecutable, const <String>[
      'build',
      '--locked',
      '-p',
      'alera-cli',
      '--release',
    ], workingDirectory: _rustDir);
    if (cargoExit != 0) {
      return cargoExit;
    }
    return _stageCliBinary(outputDir ?? _options.bundleDir);
  }

  Future<int> _stageCliBinary(String outputDir) async {
    final source = File(
      _join(_rustDir, 'target', 'release', _cliExecutableName),
    );
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
    await source.copy(destination.path);
    if (!Platform.isWindows) {
      await _run('chmod', <String>['755', destination.path]);
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

  Future<int> gpuiDebug() async {
    final manifest = _join(
      _repoRoot,
      'experiments',
      'alera-gpui',
      'Cargo.toml',
    );
    final environment = Map<String, String>.of(Platform.environment);
    if (Platform.isMacOS) {
      final toolchain = await _metalToolchainIdentifier();
      if (toolchain == null) {
        stderr.writeln(
          'The optional Xcode Metal Toolchain is required. Run '
          '`xcodebuild -downloadComponent MetalToolchain`.',
        );
        return 1;
      }
      environment['TOOLCHAINS'] = toolchain;
    }
    final buildExit = await _run(_options.cargoExecutable, <String>[
      'build',
      '--manifest-path',
      manifest,
      '--bin',
      'alera-gpui',
    ], environment: environment);
    if (buildExit != 0) {
      return buildExit;
    }
    final executable = _join(
      _join(_repoRoot, 'experiments', 'alera-gpui', 'target'),
      'debug',
      Platform.isWindows ? 'alera-gpui.exe' : 'alera-gpui',
    );
    if (!Platform.isMacOS) {
      return _run(executable, const <String>[], forwardStdin: true);
    }
    return _launchMacosGpuiBundle(executable, environment);
  }

  Future<int> freyaDebug() => _freyaRun(release: false);

  Future<int> freyaRelease() => _freyaRun(release: true);

  Future<int> freyaTest() async {
    final manifest = _join(
      _repoRoot,
      'experiments',
      'alera-freya',
      'Cargo.toml',
    );
    return _run(_options.cargoExecutable, <String>[
      'test',
      '--manifest-path',
      manifest,
    ]);
  }

  Future<int> _freyaRun({required bool release}) async {
    final manifest = _join(
      _repoRoot,
      'experiments',
      'alera-freya',
      'Cargo.toml',
    );
    final environment = Map<String, String>.of(Platform.environment);
    environment['ALERA_APP_ID'] = _freyaAppId(_options.appId);
    if (Platform.isMacOS) {
      final toolchain = await _metalToolchainIdentifier();
      if (toolchain == null) {
        stderr.writeln(
          'The optional Xcode Metal Toolchain is required. Run '
          '`xcodebuild -downloadComponent MetalToolchain`.',
        );
        return 1;
      }
      environment['TOOLCHAINS'] = toolchain;
    }
    final arguments = <String>[
      'build',
      '--manifest-path',
      manifest,
      '--bin',
      'alera-freya',
      if (release) '--release',
    ];
    final buildExit = await _run(
      _options.cargoExecutable,
      arguments,
      environment: environment,
    );
    if (buildExit != 0) {
      return buildExit;
    }
    final executable = _join(
      _join(_repoRoot, 'experiments', 'alera-freya', 'target'),
      release ? 'release' : 'debug',
      Platform.isWindows ? 'alera-freya.exe' : 'alera-freya',
    );
    if (!Platform.isMacOS) {
      return _run(
        executable,
        const <String>[],
        environment: environment,
        forwardStdin: true,
      );
    }
    return _launchMacosFreyaBundle(executable, environment, release: release);
  }

  Future<int> _launchMacosFreyaBundle(
    String executable,
    Map<String, String> environment, {
    required bool release,
  }) async {
    final bundle = Directory(
      _join(_repoRoot, '.dart_tool', 'alera_freya', 'Alera Freya.app'),
    );
    final bundledExecutable = _join(
      bundle.path,
      'Contents',
      'MacOS',
      'Alera Freya',
    );
    final targetExecutable = File(executable).absolute.path;
    await _stopRunningMacosFreya(targetExecutable);
    if (await bundle.exists()) {
      await bundle.delete(recursive: true);
    }
    final contents = Directory(_join(bundle.path, 'Contents'));
    final macos = Directory(_join(contents.path, 'MacOS'));
    await macos.create(recursive: true);
    final runtimeDir =
        environment['ALERA_RUNTIME_DIR'] ??
        _join(_defaultAppSupportDir(_options.appId), 'terminal_host');
    await File(_join(contents.path, 'Info.plist')).writeAsString(
      _freyaMacosInfoPlist(_options.appId, runtimeDir, release: release),
      flush: true,
    );
    await File(targetExecutable).copy(bundledExecutable);
    await _run('chmod', <String>['755', bundledExecutable]);
    final signExit = await _run('codesign', <String>[
      '--force',
      '--deep',
      '--sign',
      '-',
      bundle.path,
    ]);
    if (signExit != 0) {
      return signExit;
    }
    final launch = await Process.run('open', <String>['-n', bundle.path]);
    if (launch.exitCode != 0) {
      stderr.write(launch.stderr);
      return launch.exitCode;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var pids = <int>[];
    while (pids.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      pids = await _macosFreyaPids(targetExecutable);
    }
    if (pids.length != 1) {
      stderr.writeln(
        'Expected one Alera Freya process after launch, found ${pids.length}.',
      );
      return 1;
    }
    stdout.writeln(
      'Started Alera Freya pid ${pids.single} from ${bundle.path}.',
    );
    return 0;
  }

  Future<void> _stopRunningMacosFreya(String executable) async {
    final pids = await _macosFreyaPids(executable);
    for (final pid in pids) {
      Process.killPid(pid);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if ((await _macosFreyaPids(executable)).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('The previous Alera Freya process did not exit.');
  }

  Future<List<int>> _macosFreyaPids(String executable) async {
    final bundledExecutable = _join(
      _join(_repoRoot, '.dart_tool', 'alera_freya', 'Alera Freya.app'),
      'Contents',
      'MacOS',
      'Alera Freya',
    );
    final pids = <int>{};
    for (final candidate in <String>[executable, bundledExecutable]) {
      final result = await Process.run('pgrep', <String>['-f', candidate]);
      if (result.exitCode != 0) {
        continue;
      }
      pids.addAll(
        result.stdout.toString().split('\n').map(int.tryParse).whereType<int>(),
      );
    }
    return pids.toList(growable: false);
  }

  Future<String?> _metalToolchainIdentifier() async {
    final result = await Process.run('xcodebuild', const <String>[
      '-showComponent',
      'MetalToolchain',
    ], workingDirectory: _repoRoot);
    if (result.exitCode != 0) {
      return null;
    }
    final match = RegExp(
      r'^Toolchain Identifier:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(result.stdout.toString());
    return match?.group(1);
  }

  Future<int> _launchMacosGpuiBundle(
    String executable,
    Map<String, String> environment,
  ) async {
    final bundle = Directory(
      _join(_repoRoot, '.dart_tool', 'alera_gpui', 'Alera GPUI.app'),
    );
    final bundledExecutable = _join(
      bundle.path,
      'Contents',
      'MacOS',
      'Alera GPUI',
    );
    final targetExecutable = File(executable).absolute.path;
    await _stopRunningMacosGpui(targetExecutable);
    if (await bundle.exists()) {
      await bundle.delete(recursive: true);
    }
    final contents = Directory(_join(bundle.path, 'Contents'));
    final macos = Directory(_join(contents.path, 'MacOS'));
    await macos.create(recursive: true);
    final runtimeDir =
        environment['ALERA_RUNTIME_DIR'] ??
        _join(_defaultAppSupportDir(_options.appId), 'terminal_host');
    await File(_join(contents.path, 'Info.plist')).writeAsString(
      _gpuiMacosInfoPlist(_options.appId, runtimeDir),
      flush: true,
    );
    await File(targetExecutable).copy(bundledExecutable);
    await _run('chmod', <String>['755', bundledExecutable]);
    final signExit = await _run('codesign', <String>[
      '--force',
      '--deep',
      '--sign',
      '-',
      bundle.path,
    ]);
    if (signExit != 0) {
      return signExit;
    }

    final launch = await Process.run('open', <String>['-n', bundle.path]);
    if (launch.exitCode != 0) {
      stderr.write(launch.stderr);
      return launch.exitCode;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var pids = <int>[];
    while (pids.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      pids = await _macosGpuiPids(targetExecutable);
    }
    if (pids.length != 1) {
      stderr.writeln(
        'Expected one Alera GPUI process after launch, found ${pids.length}.',
      );
      return 1;
    }
    stdout.writeln(
      'Started Alera GPUI pid ${pids.single} from ${bundle.path}.',
    );
    return 0;
  }

  Future<void> _stopRunningMacosGpui(String executable) async {
    final pids = await _macosGpuiPids(executable);
    for (final pid in pids) {
      Process.killPid(pid);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if ((await _macosGpuiPids(executable)).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('The previous Alera GPUI process did not exit.');
  }

  Future<List<int>> _macosGpuiPids(String executable) async {
    final bundledExecutable = _join(
      _join(_repoRoot, '.dart_tool', 'alera_gpui', 'Alera GPUI.app'),
      'Contents',
      'MacOS',
      'Alera GPUI',
    );
    final pids = <int>{};
    for (final candidate in <String>[executable, bundledExecutable]) {
      final result = await Process.run('pgrep', <String>['-f', candidate]);
      if (result.exitCode != 0) {
        continue;
      }
      pids.addAll(
        result.stdout.toString().split('\n').map(int.tryParse).whereType<int>(),
      );
    }
    return pids.toList(growable: false);
  }

  static String _gpuiMacosInfoPlist(String appId, String runtimeDir) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Alera GPUI</string>
  <key>CFBundleExecutable</key>
  <string>Alera GPUI</string>
  <key>CFBundleIdentifier</key>
  <string>${_gpuiBundleIdentifier(appId)}</string>
  <key>CFBundleName</key>
  <string>Alera GPUI</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSEnvironment</key>
  <dict>
    <key>ALERA_APP_ID</key>
    <string>${_xmlEscape(appId)}</string>
    <key>ALERA_RUNTIME_DIR</key>
    <string>${_xmlEscape(runtimeDir)}</string>
  </dict>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Allow Alera To Open Workspaces Stored On Your Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Allow Alera To Open Workspaces Stored In Documents.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Allow Alera To Open Workspaces Stored In Downloads.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>Allow Alera To Open Workspaces Stored On External Volumes.</string>
</dict>
</plist>
''';

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _gpuiBundleIdentifier(String appId) {
    for (final suffix in const <String>['.dev', '.test']) {
      if (appId.endsWith(suffix)) {
        return '${appId.substring(0, appId.length - suffix.length)}.gpui$suffix';
      }
    }
    return '$appId.gpui';
  }

  static String _freyaAppId(String appId) {
    for (final suffix in const <String>['.dev', '.test']) {
      if (appId.endsWith(suffix)) {
        return '${appId.substring(0, appId.length - suffix.length)}.freya$suffix';
      }
    }
    return '$appId.freya';
  }

  static String _freyaMacosInfoPlist(
    String appId,
    String runtimeDir, {
    required bool release,
  }) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Alera Freya</string>
  <key>CFBundleExecutable</key>
  <string>Alera Freya</string>
  <key>CFBundleIdentifier</key>
  <string>${_freyaAppId(appId)}</string>
  <key>CFBundleName</key>
  <string>Alera Freya</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>${release ? '1' : '0'}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSEnvironment</key>
  <dict>
    <key>ALERA_APP_ID</key>
    <string>${_xmlEscape(_freyaAppId(appId))}</string>
    <key>ALERA_RUNTIME_DIR</key>
    <string>${_xmlEscape(runtimeDir)}</string>
  </dict>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
''';

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
