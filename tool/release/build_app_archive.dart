import 'dart:convert';
import 'dart:io';

const _platforms = <String>['macos', 'windows', 'linux'];

void main(List<String> args) {
  final outputPath = args.isEmpty ? 'public/app-archive.json' : args.first;
  final releaseVersion = _requiredEnv('ALERA_RELEASE_VERSION');
  final artifactVersion =
      Platform.environment['ALERA_ARTIFACT_VERSION'] ??
      releaseVersion.split('-').first;
  final buildNumber = int.parse(_requiredEnv('ALERA_RELEASE_BUILD_NUMBER'));
  final baseUrl = _trimTrailingSlash(
    Platform.environment['ALERA_UPDATE_BASE_URL'] ??
        'https://leynier.github.io/alera',
  );
  final releaseDate =
      Platform.environment['ALERA_RELEASE_DATE'] ??
      DateTime.now().toUtc().toIso8601String().split('T').first;
  final mandatory =
      (Platform.environment['ALERA_RELEASE_MANDATORY'] ?? 'false') == 'true';
  final changes = _changesFromEnvironment(releaseVersion);

  final archive = <String, Object?>{
    'appName': 'Alera',
    'description': 'Alera desktop agentic development environment.',
    'items': [
      for (final platform in _platforms)
        <String, Object?>{
          'version': releaseVersion,
          'shortVersion': buildNumber,
          'changes': changes,
          'date': releaseDate,
          'mandatory': mandatory,
          'url': '$baseUrl/updates/$artifactVersion+$buildNumber-$platform',
          'platform': platform,
        },
    ],
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
