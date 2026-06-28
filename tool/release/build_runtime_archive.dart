import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _platforms = <String>{'macos', 'windows', 'linux'};
const _architectures = <String>{'x64', 'arm64'};

void main(List<String> args) {
  final outputPath = args.isEmpty ? 'public/runtime-archive.json' : args.first;
  final releaseVersion = _requiredEnv('ALERA_RELEASE_VERSION');
  final buildNumber = int.parse(_requiredEnv('ALERA_RELEASE_BUILD_NUMBER'));
  final channel = Platform.environment['ALERA_RELEASE_CHANNEL'] ?? 'stable';
  final releaseDate =
      Platform.environment['ALERA_RELEASE_DATE'] ??
      DateTime.now().toUtc().toIso8601String().split('T').first;
  final assetsDir = Directory(
    Platform.environment['ALERA_RELEASE_ASSETS_DIR'] ?? 'release-assets',
  );
  final baseUrl = _trimTrailingSlash(
    Platform.environment['ALERA_RUNTIME_RELEASE_BASE_URL'] ??
        'https://github.com/leynier/alera/releases/download/v$releaseVersion',
  );

  if (!assetsDir.existsSync()) {
    stderr.writeln('Missing release assets directory: ${assetsDir.path}');
    exit(1);
  }

  final items = <Map<String, Object?>>[];
  final artifactPattern = RegExp(
    r'^alera-runtime-(.+)-(macos|windows|linux)-([A-Za-z0-9_.-]+)\.tar\.gz$',
  );
  final files =
      assetsDir
          .listSync()
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith('alera-runtime-'))
          .where((file) => p.basename(file.path).endsWith('.tar.gz'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  for (final file in files) {
    final name = p.basename(file.path);
    final match = artifactPattern.firstMatch(name);
    if (match == null) {
      stderr.writeln('Unsupported runtime artifact name: $name');
      exit(1);
    }
    final version = match.group(1)!;
    final platform = match.group(2)!;
    final arch = match.group(3)!;
    if (version != releaseVersion) {
      stderr.writeln(
        'Runtime artifact $name has version $version, expected $releaseVersion.',
      );
      exit(1);
    }
    items.add(<String, Object?>{
      'version': version,
      'platform': platform,
      'arch': arch,
      'artifactName': name,
      'url': '$baseUrl/$name',
      'sha256': sha256.convert(file.readAsBytesSync()).toString(),
      'size': file.lengthSync(),
    });
  }

  final pairs = items
      .map((item) => '${item['platform']}/${item['arch']}')
      .toSet();
  final requiredPairs = <String>{
    for (final platform in _platforms)
      for (final arch in _architectures) '$platform/$arch',
  };
  final missing = requiredPairs.difference(pairs);
  if (missing.isNotEmpty) {
    stderr.writeln('Missing runtime artifacts: ${missing.join(', ')}');
    exit(1);
  }

  final archive = <String, Object?>{
    'schemaVersion': 1,
    'appName': 'Alera Runtime',
    'description': 'Standalone Alera runtime sidecar artifacts.',
    'channel': channel,
    'version': releaseVersion,
    'buildNumber': buildNumber,
    'publishedAt': '${releaseDate}T00:00:00Z',
    'items': items,
  };

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(archive));
  stdout.writeln('Wrote ${output.path}');
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('$name must be set.');
    exit(64);
  }
  return value;
}

String _trimTrailingSlash(String value) {
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
