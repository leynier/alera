import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart tool/release/update_mobile_pubspec_version.dart '
      '<version> <buildNumber>',
    );
    exitCode = 64;
    return;
  }

  final version = args[0].trim();
  final buildNumber = int.tryParse(args[1].trim());
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    stderr.writeln('Version must use X.Y.Z format.');
    exitCode = 64;
    return;
  }
  if (buildNumber == null || buildNumber < 1) {
    stderr.writeln('Build number must be a positive integer.');
    exitCode = 64;
    return;
  }

  updateMobilePubspecVersion(version, buildNumber);
}

void updateMobilePubspecVersion(
  String version,
  int buildNumber, {
  String pubspecPath = 'mobile/pubspec.yaml',
}) {
  final file = File(pubspecPath);
  final current = file.readAsStringSync();
  final updated = current.replaceFirst(
    RegExp(r'^version:\s*.+$', multiLine: true),
    'version: $version+$buildNumber',
  );
  if (updated == current &&
      !current.contains('version: $version+$buildNumber')) {
    throw StateError('Could not find a version line in $pubspecPath.');
  }

  file.writeAsStringSync(updated);
  stdout.writeln('Updated $pubspecPath to $version+$buildNumber');
}
