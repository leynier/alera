import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';

const _requiredPlatforms = <String>{'macos', 'windows', 'linux'};
const _requiredArchitectures = <String>{'x64', 'arm64'};

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? 'public/runtime-archive.json' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path does not exist.');
    exit(1);
  }

  final source = file.readAsStringSync();
  final publicKey = Platform.environment['ALERA_UPDATE_MANIFEST_PUBLIC_KEY'];
  final normalizedPublicKey = publicKey?.trim();
  if (normalizedPublicKey != null && normalizedPublicKey.isNotEmpty) {
    final verified = await verifyAleraManifestSignature(
      manifestJson: source,
      publicKeyBase64: normalizedPublicKey,
    );
    if (!verified) {
      stderr.writeln('$path has an invalid manifest signature.');
      exit(1);
    }
  }

  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('$path must contain a JSON object.');
    exit(1);
  }

  if (decoded['schemaVersion'] != 1) {
    stderr.writeln('schemaVersion must be 1.');
    exit(1);
  }
  _requireString(decoded, 'channel');
  _requireString(decoded, 'version');
  _requireString(decoded, 'publishedAt');
  if (decoded['buildNumber'] is! int) {
    stderr.writeln('buildNumber must be an integer.');
    exit(1);
  }
  if (decoded[aleraManifestSignatureKey] is! Map) {
    stderr.writeln('A signed runtime archive requires signature metadata.');
    exit(1);
  }

  final items = decoded['items'];
  if (items is! List || items.isEmpty) {
    stderr.writeln('$path must contain a non-empty items array.');
    exit(1);
  }

  final pairs = <String>{};
  for (final item in items) {
    if (item is! Map<String, Object?>) {
      stderr.writeln('Every runtime item must be a JSON object.');
      exit(1);
    }
    _requireString(item, 'version');
    final platform = _requireString(item, 'platform');
    final arch = _requireString(item, 'arch');
    pairs.add('$platform/$arch');
    final artifactName = _requireString(item, 'artifactName');
    if (!artifactName.startsWith('alera-runtime-') ||
        !artifactName.endsWith('.tar.gz')) {
      stderr.writeln('artifactName must be an alera-runtime tarball.');
      exit(1);
    }
    _requireString(item, 'url');
    final sha = _requireString(item, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      stderr.writeln('sha256 must be a lowercase hex SHA-256 for $platform.');
      exit(1);
    }
    if (item['size'] is! int || (item['size'] as int) <= 0) {
      stderr.writeln('size must be a positive integer for $platform.');
      exit(1);
    }
  }

  final requiredPairs = <String>{
    for (final platform in _requiredPlatforms)
      for (final arch in _requiredArchitectures) '$platform/$arch',
  };
  final missing = requiredPairs.difference(pairs);
  if (missing.isNotEmpty) {
    stderr.writeln('Missing runtime artifacts: ${missing.join(', ')}');
    exit(1);
  }

  stdout.writeln('Verified signed runtime archive at $path.');
}

String _requireString(Map<String, Object?> item, String key) {
  final value = item[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  stderr.writeln('$key must be a non-empty string.');
  exit(1);
}
