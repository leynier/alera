import 'dart:convert';
import 'dart:io';

/// Pins the landing download links to the release being cut.
///
/// The landing builds asset URLs from this file, so a release that does not
/// update it leaves the download page pointing at the previous version's
/// files. Desktop and mobile move on independent version sequences, so each
/// pair is optional and only what is passed gets rewritten.
const String _dataPath = 'landing/src/data/releases.json';

const String _usage =
    'Usage: dart tool/release/update_landing_release_links.dart '
    '[--desktop-version <version> --desktop-tag <tag>] '
    '[--mobile-version <version> --mobile-tag <tag>]';

void main(List<String> args) {
  final options = _parseOptions(args);
  if (options == null) {
    stderr.writeln(_usage);
    exit(64);
  }

  final desktopVersion = options['desktop-version'];
  final desktopTag = options['desktop-tag'];
  final mobileVersion = options['mobile-version'];
  final mobileTag = options['mobile-tag'];

  if ((desktopVersion == null) != (desktopTag == null) ||
      (mobileVersion == null) != (mobileTag == null)) {
    stderr.writeln('Version and tag must be passed together for a product.');
    stderr.writeln(_usage);
    exit(64);
  }
  if (desktopVersion == null && mobileVersion == null) {
    stderr.writeln('Nothing to update: pass at least one product.');
    stderr.writeln(_usage);
    exit(64);
  }

  final file = File(_dataPath);
  if (!file.existsSync()) {
    stderr.writeln('Missing $_dataPath.');
    exit(1);
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  if (desktopVersion != null && desktopTag != null) {
    _validateVersion(desktopVersion);
    data['desktop'] = <String, String>{
      'tag': desktopTag,
      'version': desktopVersion,
    };
  }
  if (mobileVersion != null && mobileTag != null) {
    _validateVersion(mobileVersion);
    data['mobile'] = <String, String>{
      'tag': mobileTag,
      'version': mobileVersion,
    };
  }

  // Two-space indent with a trailing newline, so the diff of a release commit
  // stays one line per changed field.
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
  stdout.writeln('Updated $_dataPath');
}

void _validateVersion(String version) {
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    stderr.writeln('Version must be a stable semver core like 1.2.3.');
    exit(64);
  }
}

Map<String, String>? _parseOptions(List<String> args) {
  const known = <String>{
    '--desktop-version',
    '--desktop-tag',
    '--mobile-version',
    '--mobile-tag',
  };
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    final flag = args[index];
    if (!known.contains(flag) || index + 1 >= args.length) {
      return null;
    }
    final value = args[index + 1].trim();
    if (value.isEmpty) {
      return null;
    }
    options[flag.substring(2)] = value;
  }
  return options;
}
