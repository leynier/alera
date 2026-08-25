import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// ignore: depend_on_referenced_packages
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart tool/release/verify_desktop_update_channel.dart '
      '<public-root> <app-archive.json>',
    );
    exit(64);
  }

  final publicRoot = Directory(args[0]);
  final archiveFile = File(args[1]);
  final publicKeyId = _requiredEnv('ALERA_UPDATE_MANIFEST_PUBLIC_KEY_ID');
  final publicKeyBytes = base64Decode(
    _requiredEnv('ALERA_UPDATE_MANIFEST_PUBLIC_KEY'),
  );
  final channel = _requiredEnv('ALERA_RELEASE_CHANNEL');
  final version = _requiredEnv('ALERA_RELEASE_VERSION');
  final buildNumber = int.parse(_requiredEnv('ALERA_RELEASE_BUILD_NUMBER'));

  final index = _jsonObject(await archiveFile.readAsString(), archiveFile.path);
  if (index['schemaVersion'] != 3) {
    throw const FormatException('app-archive.json must use schemaVersion 3.');
  }
  final rawItems = index['items'];
  if (rawItems is! List || rawItems.length != 3) {
    throw FormatException(
      'app-archive.json must contain 3 items, found '
      '${rawItems is List ? rawItems.length : 0}.',
    );
  }

  final seenPlatforms = <String>{};
  for (final rawItem in rawItems) {
    if (rawItem is! Map) {
      throw const FormatException(
        'app-archive.json contains an invalid release item.',
      );
    }
    final item = Map<String, dynamic>.from(rawItem);
    final platform = item['platform'];
    if (platform is! String ||
        !seenPlatforms.add(platform) ||
        !const <String>{'linux', 'macos', 'windows'}.contains(platform)) {
      throw FormatException(
        'app-archive.json contains an invalid platform $platform.',
      );
    }
    if (item['channel'] != channel ||
        item['version'] != version ||
        item['buildNumber'] != buildNumber) {
      throw FormatException(
        'The $platform index item does not match this release.',
      );
    }
    final releaseValue = item['release'];
    if (releaseValue is! String || releaseValue.trim().isEmpty) {
      throw FormatException('The $platform index item has no release URL.');
    }

    final descriptorFile = _localFileForUrl(
      publicRoot,
      Uri.parse(releaseValue),
    );
    final descriptor = _jsonObject(
      await descriptorFile.readAsString(),
      descriptorFile.path,
    );
    _verifyDescriptorIdentity(descriptor, item, descriptorFile.path);
    await _verifySignature(
      descriptor,
      publicKeyId: publicKeyId,
      publicKeyBytes: publicKeyBytes,
    );

    final artifact = descriptor['artifact'];
    if (artifact is! Map) {
      throw FormatException('${descriptorFile.path} has no artifact object.');
    }
    final artifactJson = Map<String, dynamic>.from(artifact);
    final artifactUrl = artifactJson['url'];
    final expectedLength = artifactJson['length'];
    final expectedSha256 = artifactJson['sha256'];
    if (artifactUrl is! String ||
        expectedLength is! int ||
        expectedSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw FormatException(
        '${descriptorFile.path} has invalid artifact metadata.',
      );
    }
    final artifactFile = _localFileForUrl(publicRoot, Uri.parse(artifactUrl));
    final length = await artifactFile.length();
    if (length != expectedLength) {
      throw FormatException(
        '${artifactFile.path} has length $length, expected $expectedLength.',
      );
    }
    final digest = await sha256.bind(artifactFile.openRead()).first;
    if (digest.toString() != expectedSha256) {
      throw FormatException('${artifactFile.path} has an invalid SHA-256.');
    }
  }

  stdout.writeln(
    'Verified schema 3 desktop update channel: ${archiveFile.path}',
  );
}

void _verifyDescriptorIdentity(
  Map<String, dynamic> descriptor,
  Map<String, dynamic> item,
  String path,
) {
  if (descriptor['schemaVersion'] != 3 ||
      descriptor['version'] != item['version'] ||
      descriptor['buildNumber'] != item['buildNumber'] ||
      descriptor['platform'] != item['platform'] ||
      descriptor['channel'] != item['channel']) {
    throw FormatException('$path does not match its index item.');
  }
}

File _localFileForUrl(Directory publicRoot, Uri url) {
  if (url.scheme != 'https' ||
      url.host != 'updates.alera.build' ||
      url.query.isNotEmpty ||
      url.fragment.isNotEmpty) {
    throw FormatException('Unexpected desktop update URL: $url');
  }
  final segments = url.pathSegments.where((segment) => segment.isNotEmpty);
  return File(p.joinAll(<String>[publicRoot.path, ...segments]));
}

Future<void> _verifySignature(
  Map<String, dynamic> descriptor, {
  required String publicKeyId,
  required List<int> publicKeyBytes,
}) async {
  final rawSignature = descriptor['signature'];
  if (rawSignature is! Map) {
    throw FormatException(
      '${descriptor['platform']} release.json has no signature.',
    );
  }
  final signature = Map<String, dynamic>.from(rawSignature);
  if (signature['algorithm'] != 'ed25519' ||
      signature['publicKeyId'] != publicKeyId ||
      signature['value'] is! String) {
    throw FormatException(
      '${descriptor['platform']} release.json has an invalid signature policy.',
    );
  }

  final canonicalDescriptor = Map<String, dynamic>.from(descriptor);
  canonicalDescriptor['signature'] = <String, dynamic>{
    ...signature,
    'value': '',
  };
  final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
  final valid = await Ed25519().verify(
    utf8.encode(jsonEncode(_sortJson(canonicalDescriptor))),
    signature: Signature(
      base64Decode(signature['value'] as String),
      publicKey: publicKey,
    ),
  );
  if (!valid) {
    throw FormatException(
      '${descriptor['platform']} release.json has an invalid signature.',
    );
  }
}

Object? _sortJson(Object? value) {
  if (value is Map) {
    final sorted = <String, dynamic>{};
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    for (final key in keys) {
      sorted[key] = _sortJson(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_sortJson).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> _jsonObject(String source, String path) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw FormatException('$path must contain a JSON object.');
  }
  return Map<String, dynamic>.from(decoded);
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('$name must be set.');
  }
  return value;
}
