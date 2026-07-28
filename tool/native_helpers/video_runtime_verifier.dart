import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_helper_manifest.dart';
import 'native_helper_materializer.dart';

Future<void> verifyVideoRuntimeBundle({
  required String platform,
  required Directory bundle,
  File? manifestFile,
}) async {
  final normalized = normalizeNativeHelperPlatform(platform);
  final file =
      manifestFile ??
      File(p.join('tool', 'native_helpers', 'video_runtime_assets.json'));
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
    throw const FormatException('Invalid video runtime asset manifest.');
  }
  _verifyPackagePins(decoded);
  switch (normalized) {
    case 'macos':
      _verifyMacosVideoRuntime(decoded, bundle);
    case 'windows':
      await _verifyWindowsVideoRuntime(decoded, bundle);
    case 'linux':
      await _verifyLinuxVideoRuntime(decoded, bundle);
  }
}

void _verifyPackagePins(Map<String, Object?> manifest) {
  final expected = manifest['dartPackages'];
  if (expected is! Map<String, Object?> || expected.isEmpty) {
    throw const FormatException('Video runtime Dart package pins are missing.');
  }
  final lock = File('pubspec.lock').readAsStringSync();
  for (final entry in expected.entries) {
    if (entry.value is! String) {
      throw FormatException('${entry.key} package pin must be a string.');
    }
    final packageBlock = RegExp(
      '^  ${RegExp.escape(entry.key)}:\\n'
      r'(?:    .*\n)*?'
      '    version: "${RegExp.escape(entry.value! as String)}"\\n',
      multiLine: true,
    );
    if (!packageBlock.hasMatch(lock)) {
      throw StateError(
        '${entry.key} ${entry.value} is not pinned in pubspec.lock.',
      );
    }
  }
}

void _verifyMacosVideoRuntime(Map<String, Object?> manifest, Directory bundle) {
  final config = _requiredMap(manifest, 'macos');
  _requireSha256(config, 'sourceSha256', 'macOS libmpv source');
  if (config['gplEnabled'] != false || config['flavor'] != 'video-default') {
    throw StateError('macOS libmpv must use the non-GPL default flavor.');
  }
  final app = _macosApp(bundle);
  final frameworks = Directory(p.join(app.path, 'Contents', 'Frameworks'));
  final names = _requiredStrings(config, 'requiredFrameworks');
  for (final name in names) {
    final binary = File(
      p.join(frameworks.path, '$name.framework', 'Versions', 'A', name),
    );
    final flatBinary = File(p.join(frameworks.path, '$name.framework', name));
    if (!binary.existsSync() && !flatBinary.existsSync()) {
      throw StateError('Missing macOS video framework: $name.framework');
    }
  }
}

Future<void> _verifyWindowsVideoRuntime(
  Map<String, Object?> manifest,
  Directory bundle,
) async {
  final config = _requiredMap(manifest, 'windows');
  if (config['gplEnabled'] != false) {
    throw StateError('Windows libmpv must use a non-GPL build.');
  }
  final sources = config['sources'];
  if (sources is! List<Object?> || sources.length != 2) {
    throw const FormatException('Windows video source pins are incomplete.');
  }
  for (final source in sources) {
    if (source is! Map<String, Object?>) {
      throw const FormatException('Windows video source pin is invalid.');
    }
    _requireSha256(source, 'sha256', 'Windows video source');
  }
  final required = config['requiredFiles'];
  if (required is! List<Object?> || required.isEmpty) {
    throw const FormatException('Windows video files are missing.');
  }
  for (final value in required) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Windows video file pin is invalid.');
    }
    final relativePath = _requiredString(value, 'relativePath');
    final expected = _requireSha256(value, 'sha256', relativePath);
    final file = File(p.join(bundle.path, p.fromUri(relativePath)));
    if (!file.existsSync()) {
      throw StateError('Missing Windows video runtime: ${file.path}');
    }
    final actual = await fileSha256(file);
    if (actual != expected) {
      throw StateError(
        '$relativePath SHA-256 mismatch: expected $expected, got $actual.',
      );
    }
  }
}

Future<void> _verifyLinuxVideoRuntime(
  Map<String, Object?> manifest,
  Directory bundle,
) async {
  final config = _requiredMap(manifest, 'linux');
  final libraries = _requiredStrings(config, 'requiredLibraries');
  for (final relativePath in libraries) {
    final library = File(p.join(bundle.path, p.fromUri(relativePath)));
    if (!library.existsSync()) {
      throw StateError('Missing Linux video runtime: ${library.path}');
    }
  }
  final videoPlugin = File(
    p.join(bundle.path, 'lib', 'libmedia_kit_video_plugin.so'),
  );
  final ldd = await Process.run('ldd', <String>[videoPlugin.path]);
  if (ldd.exitCode != 0) {
    throw ProcessException(
      'ldd',
      <String>[videoPlugin.path],
      '${ldd.stderr}',
      ldd.exitCode,
    );
  }
  final dependencies = '${ldd.stdout}';
  if (dependencies.contains('not found')) {
    throw StateError(
      'Linux video runtime has missing libraries:\n$dependencies',
    );
  }
  for (final soname in _requiredStrings(config, 'requiredSonames')) {
    if (!dependencies.contains(soname)) {
      throw StateError('Linux video runtime is not linked to $soname.');
    }
  }
}

Directory _macosApp(Directory bundle) {
  if (p.extension(bundle.path).toLowerCase() == '.app') {
    return bundle;
  }
  for (final name in const <String>['Alera.app', 'alera.app']) {
    final candidate = Directory(p.join(bundle.path, name));
    if (candidate.existsSync()) {
      return candidate;
    }
  }
  throw StateError('No macOS app bundle found under ${bundle.path}.');
}

Map<String, Object?> _requiredMap(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  throw FormatException('$key must be a JSON object.');
}

List<String> _requiredStrings(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$key must be a non-empty string array.');
  }
  return value.cast<String>();
}

String _requiredString(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

String _requireSha256(Map<String, Object?> object, String key, String label) {
  final value = _requiredString(object, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$label must have a lowercase SHA-256.');
  }
  return value;
}
