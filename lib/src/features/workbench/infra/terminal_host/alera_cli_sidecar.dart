import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:path/path.dart' as p;

final class const AleraCliCommand({
  required final String executable,
  final List<String> prefixArguments = const <String>[],
  final String? workingDirectory,
});

abstract interface class AleraCliResolver {
  Future<AleraCliCommand> resolve({required String runtimeDir});
}

final class DefaultAleraCliResolver({
  Map<String, String>? environment,
  String? operatingSystem,
  String? resolvedExecutable,
  String? currentDirectoryPath,
}) implements AleraCliResolver {
  this
    : _options = _DefaultAleraCliResolverOptions(
        environment: environment,
        operatingSystem: operatingSystem,
        resolvedExecutable: resolvedExecutable,
        currentDirectoryPath: currentDirectoryPath,
      );

  final _DefaultAleraCliResolverOptions _options;

  Map<String, String>? get _environment => _options.environment;

  String? get _operatingSystem => _options.operatingSystem;

  String? get _resolvedExecutable => _options.resolvedExecutable;

  String? get _currentDirectoryPath => _options.currentDirectoryPath;

  @override
  Future<AleraCliCommand> resolve({required String runtimeDir}) async {
    final environment = _environment ?? Platform.environment;
    final override = _nonBlank(environment['ALERA_CLI_PATH']);
    if (override != null) {
      return AleraCliCommand(executable: override);
    }

    for (final candidate in _directCandidates(environment)) {
      if (await File(candidate).exists()) {
        return AleraCliCommand(executable: candidate);
      }
    }

    for (final archive in _archiveCandidates(environment)) {
      if (await File(archive).exists()) {
        return AleraCliCommand(
          executable: await _extractCompressedSidecar(
            archivePath: archive,
            runtimeDir: runtimeDir,
          ),
        );
      }
    }

    // Dev-only fallback when no bundled binary is present: build and run the
    // Rust sidecar from source via cargo. Production always finds the bundled
    // binary above, so this branch never runs in a packaged app.
    return AleraCliCommand(
      executable: _nonBlank(environment['CARGO']) ?? 'cargo',
      prefixArguments: const <String>[
        'run',
        '--quiet',
        '--locked',
        '--manifest-path',
        'rust/Cargo.toml',
        '-p',
        'alera-cli',
        '--',
      ],
      workingDirectory: _currentDirectory,
    );
  }

  Iterable<String> _directCandidates(Map<String, String> environment) sync* {
    final bundleDir = _nonBlank(environment['ALERA_CLI_BUNDLE_DIR']);
    if (bundleDir != null) {
      yield p.join(bundleDir, 'bin', _executableName);
      yield p.join(bundleDir, _executableName);
    }

    final resourcesDir = _macOSResourcesDir();
    if (resourcesDir != null) {
      yield p.join(resourcesDir, 'alera', 'bin', _executableName);
      yield p.join(resourcesDir, 'alera', _executableName);
    }

    final executableDir = p.dirname(_resolvedExecutablePath);
    yield p.join(executableDir, 'resources', 'alera', 'bin', _executableName);
    yield p.join(executableDir, 'resources', 'alera', _executableName);
    yield p.join(executableDir, 'alera', 'bin', _executableName);
    yield p.join(executableDir, 'alera', _executableName);
    yield p.join(
      _currentDirectory,
      '.dart_tool',
      'alera',
      'bundle',
      'bin',
      _executableName,
    );
    yield p.join(_currentDirectory, '.dart_tool', 'alera', _executableName);
    yield p.join(
      _currentDirectory,
      'build',
      'alera_cli',
      _operatingSystemName,
      'bundle',
      'bin',
      _executableName,
    );
    yield p.join(
      _currentDirectory,
      'build',
      'alera_cli',
      _operatingSystemName,
      _executableName,
    );
  }

  Iterable<String> _archiveCandidates(Map<String, String> environment) sync* {
    final bundleDir = _nonBlank(environment['ALERA_CLI_BUNDLE_DIR']);
    if (bundleDir != null) {
      yield p.join(bundleDir, '$_executableName.gz');
    }

    final resourcesDir = _macOSResourcesDir();
    if (resourcesDir != null) {
      yield p.join(resourcesDir, 'alera', '$_executableName.gz');
    }

    final executableDir = p.dirname(_resolvedExecutablePath);
    yield p.join(executableDir, 'resources', 'alera', '$_executableName.gz');
    yield p.join(executableDir, 'alera', '$_executableName.gz');
  }

  Future<String> _extractCompressedSidecar({
    required String archivePath,
    required String runtimeDir,
  }) async {
    final archive = File(archivePath);
    final stat = await archive.stat();
    final cacheRoot = Directory(p.join(p.dirname(runtimeDir), 'cli'));
    final cacheKey = [
      p
          .basenameWithoutExtension(archive.path)
          .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'),
      stat.size,
      stat.modified.millisecondsSinceEpoch,
    ].join('-');
    final cacheDir = Directory(p.join(cacheRoot.path, cacheKey));
    final target = File(p.join(cacheDir.path, _executableName));
    if (await target.exists()) {
      return target.path;
    }

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final bytes = gzip.decode(await archive.readAsBytes());
    await target.writeAsBytes(bytes, flush: true);
    if (_operatingSystemName != 'windows' && !Platform.isWindows) {
      setPosixFileMode(target.path, posixExecutableFileMode);
    }
    return target.path;
  }

  String? _macOSResourcesDir() {
    if (_operatingSystemName != 'macos') {
      return null;
    }
    final marker = '${p.separator}Contents${p.separator}MacOS${p.separator}';
    final index = _resolvedExecutablePath.indexOf(marker);
    if (index < 0) {
      return null;
    }
    return p.join(
      _resolvedExecutablePath.substring(0, index),
      'Contents',
      'Resources',
    );
  }

  String get _executableName {
    return _operatingSystemName == 'windows'
        ? aleraCliWindowsExecutableName
        : aleraCliExecutableName;
  }

  String get _operatingSystemName =>
      _operatingSystem ?? Platform.operatingSystem;

  String get _resolvedExecutablePath =>
      _resolvedExecutable ?? Platform.resolvedExecutable;

  String get _currentDirectory =>
      _currentDirectoryPath ?? Directory.current.path;
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

final class const _DefaultAleraCliResolverOptions({
  required final Map<String, String>? environment,
  required final String? operatingSystem,
  required final String? resolvedExecutable,
  required final String? currentDirectoryPath,
});
