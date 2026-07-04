import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AleraCliRegistrationSupportDirectoryResolver =
    Future<Directory> Function();
typedef AleraCliRegistrationCommandEnvironmentResolverFactory =
    CommandEnvironmentResolver Function();

enum AleraCliRegistrationState {
  installed,
  notInstalled,
  stale,
  conflict,
  unsupported,
}

enum AleraCliRegistrationInstallMethod { wrapper }

class AleraCliRegistrationStatus {
  const AleraCliRegistrationStatus({
    required this.commandName,
    required this.commandPath,
    required this.pathDirectory,
    required this.pathConfigured,
    required this.launcherPath,
    required this.installMethod,
    required this.state,
    required this.detail,
  });

  final String commandName;
  final String? commandPath;
  final String? pathDirectory;
  final bool pathConfigured;
  final String? launcherPath;
  final AleraCliRegistrationInstallMethod? installMethod;
  final AleraCliRegistrationState state;
  final String? detail;

  bool get supported => state != AleraCliRegistrationState.unsupported;

  bool get ready =>
      state == AleraCliRegistrationState.installed && pathConfigured;

  String get summary {
    if (ready) {
      return 'Registered On PATH';
    }
    return switch (state) {
      AleraCliRegistrationState.installed => 'Registered, Add To PATH',
      AleraCliRegistrationState.notInstalled => 'Not Registered',
      AleraCliRegistrationState.stale => 'Registration Needs Update',
      AleraCliRegistrationState.conflict => 'Registration Conflict',
      AleraCliRegistrationState.unsupported => 'Registration Unsupported',
    };
  }
}

class AleraCliRegistrationService {
  AleraCliRegistrationService({
    AleraCliResolver? cliResolver,
    CommandEnvironmentResolver? commandEnvironmentResolver,
    AleraCliRegistrationCommandEnvironmentResolverFactory?
    commandEnvironmentResolverFactory,
    required this.processRunner,
    AleraCliRegistrationSupportDirectoryResolver? applicationSupportDirectory,
    Map<String, String>? environment,
    String? operatingSystem,
    this.homePath,
    this.localAppDataPath,
  }) : _cliResolver = cliResolver ?? DefaultAleraCliResolver(),
       _commandEnvironmentResolverFactory =
           commandEnvironmentResolverFactory ??
           (() =>
               commandEnvironmentResolver ?? UserCommandEnvironmentResolver()),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _environment = environment ?? Platform.environment,
       _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  static const String commandName = 'alera';
  static const String _wrapperMarker = 'ALERA_CLI_WRAPPER=1';

  final AleraCliResolver _cliResolver;
  final AleraCliRegistrationCommandEnvironmentResolverFactory
  _commandEnvironmentResolverFactory;
  final AleraCliRegistrationSupportDirectoryResolver
  _applicationSupportDirectory;
  final Map<String, String> _environment;
  final String _operatingSystem;
  final ProcessRunner processRunner;
  final String? homePath;
  final String? localAppDataPath;

  Future<AleraCliRegistrationStatus> status() async {
    final spec = await _spec();
    if (spec == null) {
      return const AleraCliRegistrationStatus(
        commandName: commandName,
        commandPath: null,
        pathDirectory: null,
        pathConfigured: false,
        launcherPath: null,
        installMethod: null,
        state: AleraCliRegistrationState.unsupported,
        detail: 'CLI Registration Is Not Supported On This Platform.',
      );
    }

    final expected = _wrapperSource(spec);
    final file = File(spec.commandPath);
    final pathResolution = await _resolvePath(spec.commandPath);
    final pathConfigured = pathResolution.pathConfigured;
    if (!await file.exists()) {
      return _statusFor(
        spec,
        pathConfigured: pathConfigured,
        state: AleraCliRegistrationState.notInstalled,
        detail:
            'Register The Alera Command To Use It From Terminals And Agents.',
      );
    }
    final String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      return _statusFor(
        spec,
        pathConfigured: pathConfigured,
        state: AleraCliRegistrationState.conflict,
        detail: '${spec.commandPath} Exists But Is Not Readable As Text.',
      );
    }
    if (content == expected) {
      if (!await _isExecutable(spec.commandPath)) {
        return _statusFor(
          spec,
          pathConfigured: false,
          state: AleraCliRegistrationState.stale,
          detail:
              '${spec.commandPath} Is Registered But Is Not Executable. Update Registration To Repair Permissions.',
        );
      }
      final shadowingCommandPath = pathResolution.shadowingCommandPath;
      if (shadowingCommandPath != null) {
        return _statusFor(
          spec,
          pathConfigured: false,
          state: AleraCliRegistrationState.conflict,
          detail:
              '$shadowingCommandPath Is Earlier On PATH Than ${spec.commandPath}.',
        );
      }
      return _statusFor(
        spec,
        pathConfigured: pathConfigured,
        state: AleraCliRegistrationState.installed,
        detail: pathConfigured
            ? 'Registered At ${spec.commandPath}.'
            : 'Registered At ${spec.commandPath}. Add ${p.dirname(spec.commandPath)} To PATH.',
      );
    }
    if (content.contains(_wrapperMarker)) {
      return _statusFor(
        spec,
        pathConfigured: pathConfigured,
        state: AleraCliRegistrationState.stale,
        detail: '${spec.commandPath} Points To An Older Alera Launcher.',
      );
    }
    return _statusFor(
      spec,
      pathConfigured: pathConfigured,
      state: AleraCliRegistrationState.conflict,
      detail: '${spec.commandPath} Exists But Is Not Managed By Alera.',
    );
  }

  Future<AleraCliRegistrationStatus> installOrUpdate() async {
    final spec = await _spec();
    if (spec == null) {
      return status();
    }
    final current = await status();
    if (current.state == AleraCliRegistrationState.conflict) {
      return current;
    }
    final file = File(spec.commandPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(_wrapperSource(spec), flush: true);
    if (_operatingSystem != 'windows') {
      final chmod = await processRunner.run('chmod', <String>[
        '755',
        file.path,
      ]);
      if (chmod.exitCode != 0) {
        return _statusFor(
          spec,
          pathConfigured: (await _resolvePath(spec.commandPath)).pathConfigured,
          state: AleraCliRegistrationState.stale,
          detail: chmod.stderr.trim().isEmpty
              ? 'Registered File Was Written, But Permissions Update Failed.'
              : 'Registered File Was Written, But Permissions Update Failed: ${chmod.stderr.trim()}',
        );
      }
    }
    return status();
  }

  Future<AleraCliRegistrationStatus> remove() async {
    final spec = await _spec();
    if (spec == null) {
      return status();
    }
    final current = await status();
    if (current.state == AleraCliRegistrationState.conflict) {
      return current;
    }
    final file = File(spec.commandPath);
    if (await file.exists()) {
      await file.delete();
    }
    return status();
  }

  Future<_AleraCliRegistrationSpec?> _spec() async {
    final commandPath = _commandPath();
    if (commandPath == null) {
      return null;
    }
    final support = await _applicationSupportDirectory();
    final runtimeDir = p.join(support.path, 'terminal_host');
    final launcher = await _cliResolver.resolve(runtimeDir: runtimeDir);
    return _AleraCliRegistrationSpec(
      commandPath: commandPath,
      runtimeDir: runtimeDir,
      launcher: launcher,
    );
  }

  String? _commandPath() {
    final override = _nonBlank(_environment['ALERA_CLI_INSTALL_PATH']);
    if (override != null) {
      return override;
    }
    final home =
        homePath ?? _environment['HOME'] ?? _environment['USERPROFILE'];
    if (_operatingSystem == 'windows') {
      final localAppData =
          localAppDataPath ??
          _environment['LOCALAPPDATA'] ??
          (home == null ? null : p.join(home, 'AppData', 'Local'));
      return localAppData == null
          ? null
          : p.join(localAppData, 'Programs', 'Alera', 'bin', 'alera.cmd');
    }
    return home == null ? null : p.join(home, '.local', 'bin', commandName);
  }

  Future<_AleraCliPathResolution> _resolvePath(String commandPath) async {
    final environment = await _commandEnvironmentResolverFactory()
        .environment();
    final pathValue = _pathValue(environment);
    if (pathValue == null || pathValue.isEmpty) {
      return const _AleraCliPathResolution(pathConfigured: false);
    }
    final targetDirectory = _normalizePath(p.dirname(commandPath));
    final targetPath = _normalizePath(commandPath);
    var directoryConfigured = false;
    for (final directory in pathValue.split(_pathListSeparator)) {
      if (directory.isEmpty) {
        continue;
      }
      if (_normalizePath(directory) == targetDirectory) {
        directoryConfigured = true;
      }
      for (final candidatePath in _commandCandidatePaths(directory)) {
        if (!await File(candidatePath).exists()) {
          continue;
        }
        if (!await _canResolveAsCommand(candidatePath)) {
          continue;
        }
        if (_normalizePath(candidatePath) == targetPath) {
          return const _AleraCliPathResolution(pathConfigured: true);
        }
        return _AleraCliPathResolution(
          pathConfigured: false,
          shadowingCommandPath: candidatePath,
        );
      }
    }
    return _AleraCliPathResolution(pathConfigured: directoryConfigured);
  }

  String? _pathValue(Map<String, String> environment) {
    if (_operatingSystem == 'windows') {
      return environment['Path'] ?? environment['PATH'];
    }
    return environment['PATH'];
  }

  String _normalizePath(String value) {
    final normalized = p.normalize(value);
    return _operatingSystem == 'windows'
        ? normalized.toLowerCase()
        : normalized;
  }

  String get _pathListSeparator => _operatingSystem == 'windows' ? ';' : ':';

  List<String> _commandCandidatePaths(String directory) {
    if (_operatingSystem == 'windows') {
      return <String>[
        p.join(directory, commandName),
        p.join(directory, '$commandName.com'),
        p.join(directory, '$commandName.exe'),
        p.join(directory, '$commandName.bat'),
        p.join(directory, '$commandName.cmd'),
      ];
    }
    return <String>[p.join(directory, commandName)];
  }

  Future<bool> _canResolveAsCommand(String path) async {
    if (_operatingSystem == 'windows') {
      return true;
    }
    return _isExecutable(path);
  }

  Future<bool> _isExecutable(String path) async {
    if (_operatingSystem == 'windows') {
      return true;
    }
    final stat = await File(path).stat();
    const executeMask = 0x49;
    return (stat.mode & executeMask) != 0;
  }

  AleraCliRegistrationStatus _statusFor(
    _AleraCliRegistrationSpec spec, {
    required bool pathConfigured,
    required AleraCliRegistrationState state,
    required String detail,
  }) {
    return AleraCliRegistrationStatus(
      commandName: commandName,
      commandPath: spec.commandPath,
      pathDirectory: p.dirname(spec.commandPath),
      pathConfigured: pathConfigured,
      launcherPath: spec.launcher.executable,
      installMethod: AleraCliRegistrationInstallMethod.wrapper,
      state: state,
      detail: detail,
    );
  }

  String _wrapperSource(_AleraCliRegistrationSpec spec) {
    return _operatingSystem == 'windows'
        ? _windowsWrapperSource(spec)
        : _posixWrapperSource(spec);
  }

  String _posixWrapperSource(_AleraCliRegistrationSpec spec) {
    final lines = <String>[
      '#!/bin/sh',
      '# Generated by Alera. Do not edit.',
      '# $_wrapperMarker',
      'export ALERA_RUNTIME_DIR=${_shQuote(spec.runtimeDir)}',
      if (spec.launcher.workingDirectory != null)
        'cd ${_shQuote(spec.launcher.workingDirectory!)} || exit \$?',
      'exec ${_shQuote(spec.launcher.executable)} ${spec.launcher.prefixArguments.map(_shQuote).join(' ')} "\$@"',
      '',
    ];
    return lines.join('\n');
  }

  String _windowsWrapperSource(_AleraCliRegistrationSpec spec) {
    final lines = <String>[
      '@echo off',
      'rem Generated by Alera. Do not edit.',
      'rem $_wrapperMarker',
      'set "ALERA_RUNTIME_DIR=${_cmdQuoteValue(spec.runtimeDir)}"',
      if (spec.launcher.workingDirectory != null)
        'cd /d "${_cmdQuoteValue(spec.launcher.workingDirectory!)}" || exit /b %ERRORLEVEL%',
      '"${_cmdQuoteValue(spec.launcher.executable)}" ${spec.launcher.prefixArguments.map((arg) => '"${_cmdQuoteValue(arg)}"').join(' ')} %*',
      'exit /b %ERRORLEVEL%',
      '',
    ];
    return lines.join('\r\n');
  }
}

class _AleraCliRegistrationSpec {
  const _AleraCliRegistrationSpec({
    required this.commandPath,
    required this.runtimeDir,
    required this.launcher,
  });

  final String commandPath;
  final String runtimeDir;
  final AleraCliCommand launcher;
}

class _AleraCliPathResolution {
  const _AleraCliPathResolution({
    required this.pathConfigured,
    this.shadowingCommandPath,
  });

  final bool pathConfigured;
  final String? shadowingCommandPath;
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String _shQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _cmdQuoteValue(String value) {
  return value.replaceAll('"', r'\"');
}
