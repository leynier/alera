import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _platformArchitectures = <String, Set<String>>{
  'macos': <String>{'x64', 'arm64'},
  'windows': <String>{'x64', 'arm64'},
  'linux': <String>{'x64', 'arm64'},
};

void main(List<String> args) {
  try {
    final options = _Options.parse(args);
    packageRuntimeSidecars(
      version: options.version,
      inputDirectory: Directory(options.input),
      outputDirectory: Directory(options.output),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_Options.usage);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

void packageRuntimeSidecars({
  required String version,
  required Directory inputDirectory,
  required Directory outputDirectory,
}) {
  if (version.trim().isEmpty || version != version.trim()) {
    throw StateError('Runtime version must be non-empty and trimmed.');
  }
  if (!inputDirectory.existsSync()) {
    throw StateError('Missing runtime input directory: ${inputDirectory.path}');
  }
  _validateInputLayout(inputDirectory);
  outputDirectory.createSync(recursive: true);

  for (final platform in _platformArchitectures.keys) {
    final helperDirectory = _findPlatformHelpers(inputDirectory, platform);
    for (final architecture in _platformArchitectures[platform]!) {
      final input = Directory(
        p.join(inputDirectory.path, platform, architecture),
      );
      final binaryName = platform == 'windows' ? 'alera.exe' : 'alera';
      final binary = File(p.join(input.path, binaryName));
      if (!binary.existsSync() || binary.lengthSync() == 0) {
        throw StateError(
          'Missing runtime binary for $platform/$architecture: ${binary.path}',
        );
      }

      final archive = Archive();
      archive.addFile(
        _archiveFile(binaryName, binary.readAsBytesSync(), mode: 0x1ed),
      );
      final helperFiles =
          helperDirectory
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      if (helperFiles.isEmpty) {
        throw StateError('Native helper bundle for $platform is empty.');
      }
      for (final helper in helperFiles) {
        final relative = p
            .relative(helper.path, from: helperDirectory.path)
            .split(p.separator)
            .join('/');
        final sourceMode = helper.statSync().mode & 0x1ff;
        final mode = sourceMode & 0x49 != 0 ? 0x1ed : 0x1a4;
        archive.addFile(
          _archiveFile(
            'emulator/$relative',
            helper.readAsBytesSync(),
            mode: mode,
          ),
        );
      }
      final manifest = const JsonEncoder.withIndent('  ')
          .convert(<String, Object>{
            'name': 'alera-runtime',
            'version': version,
            'platform': platform,
            'arch': architecture,
            'entrypoint': binaryName,
            'emulatorHelpers': 'emulator/manifest.json',
          });
      archive.addFile(
        _archiveFile(
          'runtime-manifest.json',
          utf8.encode('$manifest\n'),
          mode: 0x1a4,
        ),
      );

      final tar = TarEncoder().encodeBytes(archive);
      final compressed = const GZipEncoder().encodeBytes(tar);
      final assetName = 'alera-runtime-$version-$platform-$architecture.tar.gz';
      final asset = File(p.join(outputDirectory.path, assetName));
      asset.writeAsBytesSync(compressed, flush: true);
      final digest = sha256.convert(compressed);
      File(
        '${asset.path}.sha256',
      ).writeAsStringSync('$digest  $assetName\n', flush: true);
      stdout.writeln('Wrote ${asset.path}');
    }
  }
}

ArchiveFile _archiveFile(String name, List<int> bytes, {required int mode}) {
  final file = ArchiveFile.bytes(name, bytes)
    ..mode = mode
    ..ownerId = 0
    ..groupId = 0
    ..creationTime = 0
    ..lastModTime = 0;
  return file;
}

Directory _findPlatformHelpers(Directory input, String platform) {
  final candidates = <Directory>[];
  for (final architecture in _platformArchitectures[platform]!) {
    final directory = Directory(
      p.join(input.path, platform, architecture, 'emulator'),
    );
    if (directory.existsSync()) {
      candidates.add(directory);
    }
  }
  if (candidates.length != 1) {
    throw StateError(
      'Expected exactly one native helper bundle for $platform, found '
      '${candidates.length}.',
    );
  }
  final manifest = File(p.join(candidates.single.path, 'manifest.json'));
  if (!manifest.existsSync() || manifest.lengthSync() == 0) {
    throw StateError(
      'Missing native helper manifest for $platform: ${manifest.path}',
    );
  }
  return candidates.single;
}

void _validateInputLayout(Directory input) {
  final platformDirectories = input.listSync().whereType<Directory>().toList();
  final foundPlatforms = platformDirectories
      .map((directory) => p.basename(directory.path))
      .toSet();
  final unexpectedPlatforms = foundPlatforms.difference(
    _platformArchitectures.keys.toSet(),
  );
  if (unexpectedPlatforms.isNotEmpty) {
    throw StateError(
      'Unsupported runtime platforms: ${unexpectedPlatforms.join(', ')}.',
    );
  }
  for (final platform in _platformArchitectures.keys) {
    final directory = Directory(p.join(input.path, platform));
    if (!directory.existsSync()) {
      throw StateError('Missing runtime platform input: $platform.');
    }
    final foundArchitectures = directory
        .listSync()
        .whereType<Directory>()
        .map((entry) => p.basename(entry.path))
        .toSet();
    final expectedArchitectures = _platformArchitectures[platform]!;
    final unexpected = foundArchitectures.difference(expectedArchitectures);
    if (unexpected.isNotEmpty) {
      throw StateError(
        'Unsupported runtime architectures for $platform: '
        '${unexpected.join(', ')}.',
      );
    }
    final missing = expectedArchitectures.difference(foundArchitectures);
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing runtime architectures for $platform: ${missing.join(', ')}.',
      );
    }
  }
}

final class _Options {
  const _Options({
    required this.version,
    required this.input,
    required this.output,
  });

  static const usage =
      'Usage: dart tool/release/package_runtime_sidecars.dart '
      '--version <version> --input <directory> --output <directory>';

  final String version;
  final String input;
  final String output;

  static _Options parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        throw const FormatException('Invalid runtime packager arguments.');
      }
      final name = args[index].substring(2);
      if (!<String>{'version', 'input', 'output'}.contains(name) ||
          values.containsKey(name)) {
        throw FormatException('Unsupported or duplicate option: --$name.');
      }
      values[name] = args[index + 1];
    }
    for (final name in <String>['version', 'input', 'output']) {
      if (values[name]?.isNotEmpty != true) {
        throw FormatException('Missing required option: --$name.');
      }
    }
    return _Options(
      version: values['version']!,
      input: values['input']!,
      output: values['output']!,
    );
  }
}
