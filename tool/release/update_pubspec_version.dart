import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart tool/release/update_pubspec_version.dart '
      '<version> <buildNumber>',
    );
    exit(64);
  }

  final version = args[0].trim();
  final buildNumber = args[1].trim();
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    stderr.writeln('Version must be a stable semver core like 1.2.3.');
    exit(64);
  }
  if (!RegExp(r'^[1-9]\d*$').hasMatch(buildNumber)) {
    stderr.writeln('Build number must be a positive integer.');
    exit(64);
  }

  final file = File('pubspec.yaml');
  final source = file.readAsStringSync();
  final next = source.replaceFirst(
    RegExp(r'^version:\s*.+$', multiLine: true),
    'version: $version+$buildNumber',
  );

  if (next == source) {
    stderr.writeln('Could not find a version line in pubspec.yaml.');
    exit(1);
  }

  file.writeAsStringSync(next);
  stdout.writeln('Updated pubspec.yaml to $version+$buildNumber');
}
