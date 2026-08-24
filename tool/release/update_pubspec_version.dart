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

  updatePubspecVersion(version, int.parse(buildNumber));
}

void updatePubspecVersion(
  String version,
  int buildNumber, {
  String pubspecPath = 'pubspec.yaml',
}) {
  final file = File(pubspecPath);
  final source = file.readAsStringSync();
  final nextLine = 'version: $version+$buildNumber';
  final next = source.replaceFirst(
    RegExp(r'^version:\s*.+$', multiLine: true),
    nextLine,
  );

  if (next == source && !source.contains(nextLine)) {
    throw StateError('Could not find a version line in $pubspecPath.');
  }

  file.writeAsStringSync(next);
  stdout.writeln('Updated $pubspecPath to $version+$buildNumber');
}
