import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_helper_derivation.dart';

const nativeHelperBundleGenerator =
    'tool/native_helpers/prepare_native_helpers.dart';
const supportedNativeHelperPlatforms = <String>{'linux', 'macos', 'windows'};

final class NativeHelperManifest({
  required final int schemaVersion,
  required final String noticeDirectory,
  required final List<NativeHelperAsset> assets,
}) {
  factory read(File file) {
    if (!file.existsSync()) {
      throw FormatException(
        'Native helper manifest does not exist: ${file.path}',
      );
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Native helper manifest must be a JSON object.',
      );
    }
    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported native helper manifest schema: $schemaVersion',
      );
    }
    final noticeDirectory = _requiredRelativePath(decoded, 'noticeDirectory');
    final rawAssets = decoded['assets'];
    if (rawAssets is! List<Object?> || rawAssets.isEmpty) {
      throw const FormatException(
        'Native helper manifest assets must be a non-empty array.',
      );
    }
    final assets = rawAssets.map(NativeHelperAsset.fromJson).toList();
    final ids = <String>{};
    final outputPaths = <String>{};
    for (final asset in assets) {
      if (!ids.add(asset.id)) {
        throw FormatException('Duplicate native helper id: ${asset.id}');
      }
      if (!outputPaths.add(asset.relativePath)) {
        throw FormatException(
          'Duplicate native helper output path: ${asset.relativePath}',
        );
      }
    }
    return NativeHelperManifest(
      schemaVersion: 1,
      noticeDirectory: noticeDirectory,
      assets: .unmodifiableOf(assets),
    );
  }

  List<NativeHelperAsset> assetsFor(String platform) {
    final normalized = normalizeNativeHelperPlatform(platform);
    return assets
        .where((asset) => asset.platforms.contains(normalized))
        .toList(growable: false);
  }

  Map<String, Object?> bundleJson(
    String platform, {
    Map<String, String> payloadSha256ById = const <String, String>{},
  }) {
    final normalized = normalizeNativeHelperPlatform(platform);
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'generatedBy': nativeHelperBundleGenerator,
      'platform': normalized,
      'noticePath': 'NOTICE.md',
      'assets': <Object?>[
        for (final asset in assetsFor(normalized))
          <String, Object?>{
            'id': asset.id,
            'version': asset.version,
            'relativePath': asset.relativePath,
            'sha256':
                payloadSha256ById[asset.id] ??
                asset.payloadSha256 ??
                (throw StateError(
                  'Missing derived payload SHA-256 for ${asset.id}.',
                )),
            'sourceSha256': asset.sourceSha256,
            'sourceCommit': asset.sourceCommit,
            'executable': asset.executable,
            'license': asset.license,
            'licensePath': asset.licensePath,
            if (asset.derivation case final derivation?)
              'derivation': derivation.bundleJson(),
          },
      ],
    };
  }
}

final class NativeHelperAsset({
  required final String id,
  required final String version,
  required final Set<String> platforms,
  required final Uri sourceUrl,
  required final String sourceSha256,
  required final String sourceCommit,
  required final String? payloadSha256,
  required final String relativePath,
  required final String? archiveMember,
  required final bool executable,
  required final String license,
  required final String licensePath,
  required final NativeHelperDerivation? derivation,
}) {
  factory fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException(
        'Each native helper asset must be a JSON object.',
      );
    }
    final id = _requiredString(value, 'id');
    final version = _requiredString(value, 'version');
    final rawPlatforms = value['platforms'];
    if (rawPlatforms is! List<Object?> || rawPlatforms.isEmpty) {
      throw FormatException('$id platforms must be a non-empty array.');
    }
    final platforms = <String>{};
    for (final rawPlatform in rawPlatforms) {
      if (rawPlatform is! String) {
        throw FormatException('$id contains a non-string platform.');
      }
      platforms.add(normalizeNativeHelperPlatform(rawPlatform));
    }
    final sourceUrl = _requiredHttpsUri(value, 'sourceUrl', id);
    final archiveMember = value['archiveMember'];
    if (archiveMember != null && archiveMember is! String) {
      throw FormatException('$id archiveMember must be a string or null.');
    }
    if (archiveMember is String) {
      _validateRelativePath(archiveMember, '$id archiveMember');
    }
    final executable = value['executable'];
    if (executable is! bool) {
      throw FormatException('$id executable must be a boolean.');
    }
    final derivationValue = value['derivation'];
    final derivation = derivationValue == null
        ? null
        : NativeHelperDerivation.fromJson(derivationValue, assetId: id);
    final payloadSha256 = _optionalSha256(value, 'payloadSha256', id);
    if (payloadSha256 == null && derivation == null) {
      throw FormatException(
        '$id must declare payloadSha256 or a source derivation.',
      );
    }
    if (payloadSha256 != null && derivation != null) {
      throw FormatException(
        '$id cannot declare both payloadSha256 and a source derivation.',
      );
    }
    if (derivation != null) {
      if (archiveMember != null) {
        throw FormatException(
          '$id derived assets cannot declare archiveMember.',
        );
      }
      if (platforms.length != 1 || !platforms.contains('macos')) {
        throw FormatException(
          '$id Swift package derivation is supported only on macOS.',
        );
      }
    }
    return NativeHelperAsset(
      id: id,
      version: version,
      platforms: .unmodifiable(platforms),
      sourceUrl: sourceUrl,
      sourceSha256: _requiredSha256(value, 'sourceSha256', id),
      sourceCommit: _requiredCommit(value, 'sourceCommit', id),
      payloadSha256: payloadSha256,
      relativePath: _requiredRelativePath(value, 'relativePath'),
      archiveMember: archiveMember as String?,
      executable: executable,
      license: _requiredString(value, 'license'),
      licensePath: _requiredRelativePath(value, 'licensePath'),
      derivation: derivation,
    );
  }
}

String normalizeNativeHelperPlatform(String platform) {
  final normalized = platform.trim().toLowerCase();
  final alias = switch (normalized) {
    'macos' || 'mac' => 'macos',
    'windows' || 'win' => 'windows',
    'linux' => 'linux',
    _ => normalized,
  };
  if (!supportedNativeHelperPlatforms.contains(alias)) {
    throw FormatException('Unsupported native helper platform: $platform');
  }
  return alias;
}

String _requiredString(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('$key must be a non-empty string.');
}

Uri _requiredHttpsUri(Map<String, Object?> object, String key, String owner) {
  final source = Uri.tryParse(_requiredString(object, key));
  if (source == null || source.scheme != 'https' || source.host.isEmpty) {
    throw FormatException('$owner $key must use HTTPS.');
  }
  return source;
}

String _requiredRelativePath(Map<String, Object?> object, String key) {
  final value = _requiredString(object, key);
  _validateRelativePath(value, key);
  return p.posix.normalize(value);
}

void _validateRelativePath(String value, String label) {
  final normalized = p.posix.normalize(value);
  if (p.posix.isAbsolute(value) ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    throw FormatException('$label must stay inside its declared root.');
  }
}

String _requiredSha256(
  Map<String, Object?> object,
  String key,
  String assetId,
) {
  final value = _requiredString(object, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$assetId $key must be a lowercase SHA-256.');
  }
  return value;
}

String? _optionalSha256(
  Map<String, Object?> object,
  String key,
  String assetId,
) {
  if (object[key] == null) {
    return null;
  }
  return _requiredSha256(object, key, assetId);
}

String _requiredCommit(
  Map<String, Object?> object,
  String key,
  String assetId,
) {
  final value = _requiredString(object, key);
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    throw FormatException('$assetId $key must be a full Git commit hash.');
  }
  return value;
}
