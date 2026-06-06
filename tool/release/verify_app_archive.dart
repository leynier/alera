import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';

const _requiredPlatforms = <String>{'macos', 'windows', 'linux'};
const _linuxInstallers = <String>{'deb', 'rpm'};

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? 'public/app-archive.json' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path does not exist.');
    exit(1);
  }

  final source = file.readAsStringSync();
  final publicKey = Platform.environment['ALERA_UPDATE_MANIFEST_PUBLIC_KEY'];
  if (publicKey != null && publicKey.trim().isNotEmpty) {
    final verified = await verifyAleraManifestSignature(
      manifestJson: source,
      publicKeyBase64: publicKey,
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

  final schemaVersion = decoded['schemaVersion'];
  if (schemaVersion != 2) {
    stderr.writeln('schemaVersion must be 2.');
    exit(1);
  }
  final channel = _requireString(decoded, 'channel');
  _requireString(decoded, 'version');
  _requireString(decoded, 'publishedAt');
  if (decoded['buildNumber'] is! int) {
    stderr.writeln('buildNumber must be an integer.');
    exit(1);
  }
  if (decoded[aleraManifestSignatureKey] is! Map) {
    stderr.writeln('A signed schema v2 manifest requires signature metadata.');
    exit(1);
  }

  final items = decoded['items'];
  if (items is! List || items.isEmpty) {
    stderr.writeln('$path must contain a non-empty items array.');
    exit(1);
  }

  final platforms = <String>{};
  final linuxInstallers = <String>{};
  for (final item in items) {
    if (item is! Map<String, Object?>) {
      stderr.writeln('Every item must be a JSON object.');
      exit(1);
    }
    _requireString(item, 'version');
    _requireString(item, 'date');
    if (item['shortVersion'] is! int) {
      stderr.writeln('shortVersion must be an integer.');
      exit(1);
    }
    if (item['mandatory'] is! bool) {
      stderr.writeln('mandatory must be a boolean.');
      exit(1);
    }
    if (item['changes'] is! List || (item['changes'] as List).isEmpty) {
      stderr.writeln('changes must be a non-empty array.');
      exit(1);
    }
    if (item['artifacts'] != null) {
      stderr.writeln(
        'schema v2 items must use top-level url/platform fields, not artifacts.',
      );
      exit(1);
    }
    final platform = _requireString(item, 'platform');
    final installerKind = _requireString(item, 'installerKind');
    platforms.add(platform);
    if (platform == 'linux') {
      linuxInstallers.add(installerKind);
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
    _requireOptionalString(item, 'signatureBundleUrl');
    _requireOptionalString(item, 'provenanceUrl');
  }

  final missing = _requiredPlatforms.difference(platforms);
  if (missing.isNotEmpty) {
    stderr.writeln('Missing platforms: ${missing.join(', ')}');
    exit(1);
  }
  if (channel == 'stable') {
    final missingLinux = _linuxInstallers.difference(linuxInstallers);
    if (missingLinux.isNotEmpty) {
      stderr.writeln('Missing Linux installers: ${missingLinux.join(', ')}');
      exit(1);
    }
  }

  stdout.writeln('Verified signed schema v2 archive at $path.');
}

void _requireOptionalString(Map<String, Object?> item, String key) {
  if (!item.containsKey(key)) {
    return;
  }
  final value = item[key];
  if (value is String && value.trim().isNotEmpty) {
    return;
  }
  stderr.writeln('$key must be omitted or a non-empty string.');
  exit(1);
}

String _requireString(Map<String, Object?> item, String key) {
  final value = item[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  stderr.writeln('$key must be a non-empty string.');
  exit(1);
}
