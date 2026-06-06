import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _platforms = <String>['macos', 'windows', 'linux'];
const _ignoredSuffixes = <String>[
  '.intoto.jsonl',
  '.sha256',
  '.sig',
  '.sigstore',
];

void main(List<String> args) {
  final outputPath = args.isEmpty ? 'public/app-archive.json' : args.first;
  final releaseVersion = _requiredEnv('ALERA_RELEASE_VERSION');
  final artifactVersion =
      Platform.environment['ALERA_ARTIFACT_VERSION'] ??
      releaseVersion.split('-').first;
  final buildNumber = int.parse(_requiredEnv('ALERA_RELEASE_BUILD_NUMBER'));
  final baseUrl = _trimTrailingSlash(
    Platform.environment['ALERA_UPDATE_BASE_URL'] ??
        'https://updates.alera.build',
  );
  final pathPrefix = _normalizePathPrefix(
    Platform.environment['ALERA_UPDATE_PATH_PREFIX'] ?? 'updates',
  );
  final releaseDate =
      Platform.environment['ALERA_RELEASE_DATE'] ??
      DateTime.now().toUtc().toIso8601String().split('T').first;
  final mandatory =
      (Platform.environment['ALERA_RELEASE_MANDATORY'] ?? 'false') == 'true';
  final publicDir = Directory(
    Platform.environment['ALERA_RELEASE_PUBLIC_DIR'] ?? 'public',
  );
  final channelPath = pathPrefix.split('/').last;
  final changes = _changesFromEnvironment(releaseVersion);

  final items = <Map<String, Object?>>[];
  for (final platform in _platforms) {
    final artifactDir = Directory(
      p.join(
        publicDir.path,
        'updates',
        channelPath,
        '$artifactVersion+$buildNumber-$platform',
      ),
    );
    if (!artifactDir.existsSync()) {
      stderr.writeln('Missing update artifact directory: ${artifactDir.path}');
      exit(1);
    }
    final files =
        artifactDir
            .listSync()
            .whereType<File>()
            .where((file) => !_isSidecarFile(file.path))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    if (files.isEmpty) {
      stderr.writeln('No release artifacts found in ${artifactDir.path}');
      exit(1);
    }
    for (final file in files) {
      final name = p.basename(file.path);
      final relativePath = [
        pathPrefix,
        '$artifactVersion+$buildNumber-$platform',
        name,
      ].join('/');
      final url = '$baseUrl/$relativePath';
      items.add(<String, Object?>{
        'version': releaseVersion,
        'shortVersion': buildNumber,
        'changes': changes,
        'date': releaseDate,
        'mandatory': mandatory,
        'platform': platform,
        'installerKind': _installerKindFor(name),
        'url': url,
        'sha256': sha256.convert(file.readAsBytesSync()).toString(),
        'size': file.lengthSync(),
      });
    }
  }

  final archive = <String, Object?>{
    'schemaVersion': 2,
    'appName': 'Alera',
    'description': 'Alera desktop agentic development environment.',
    'channel': channelPath,
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

bool _isSidecarFile(String path) {
  return _ignoredSuffixes.any(path.endsWith);
}

String _installerKindFor(String fileName) {
  if (fileName.endsWith('.deb')) {
    return 'deb';
  }
  if (fileName.endsWith('.rpm')) {
    return 'rpm';
  }
  if (fileName.endsWith('.msi')) {
    return 'msi';
  }
  if (fileName.endsWith('.dmg')) {
    return 'dmg';
  }
  if (fileName.endsWith('.zip')) {
    return 'zip';
  }
  if (fileName.endsWith('.tar.gz')) {
    return 'tar.gz';
  }
  stderr.writeln('Unsupported release artifact type: $fileName');
  exit(1);
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

String _normalizePathPrefix(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'updates';
  }
  return trimmed.split('/').where((part) => part.trim().isNotEmpty).join('/');
}

List<Map<String, String>> _changesFromEnvironment(String releaseVersion) {
  final raw = Platform.environment['ALERA_RELEASE_NOTES']?.trim();
  final lines = raw == null || raw.isEmpty
      ? <String>['Release $releaseVersion.']
      : raw
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);

  return [
    for (final line in lines)
      <String, String>{
        'type': _typeFromLine(line),
        'message': line.replaceFirst(
          RegExp(
            r'^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|other):\s*',
          ),
          '',
        ),
      },
  ];
}

String _typeFromLine(String line) {
  final match = RegExp(
    r'^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|other):',
  ).firstMatch(line);
  return match?.group(1) ?? 'other';
}
