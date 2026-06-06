import 'dart:convert';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';

class AleraUpdateArchive {
  const AleraUpdateArchive({
    required this.appName,
    required this.items,
    this.schemaVersion = 1,
  });

  factory AleraUpdateArchive.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Update archive must be a JSON object.');
    }
    return AleraUpdateArchive.fromJson(Map<String, Object?>.from(decoded));
  }

  static Future<AleraUpdateArchive> fromSignedJsonString(
    String source, {
    required String publicKeyBase64,
  }) async {
    final verified = await verifyAleraManifestSignature(
      manifestJson: source,
      publicKeyBase64: publicKeyBase64,
    );
    if (!verified) {
      throw const FormatException('Update manifest signature is invalid.');
    }
    return AleraUpdateArchive.fromJsonString(source);
  }

  factory AleraUpdateArchive.fromJson(Map<String, Object?> json) {
    final schemaVersion = _optionalInt(json['schemaVersion']) ?? 1;
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Update archive must contain items.');
    }
    return AleraUpdateArchive(
      appName: _optionalString(json['appName']) ?? 'Alera',
      schemaVersion: schemaVersion,
      items: [
        for (final item in items)
          if (item is Map)
            ..._itemsFromJson(
              Map<String, Object?>.from(item),
              schemaVersion: schemaVersion,
            ),
      ],
    );
  }

  final String appName;
  final int schemaVersion;
  final List<AleraUpdateInfo> items;

  AleraUpdateInfo? latestFor({
    required String platform,
    required int currentBuildNumber,
    required AleraUpdateChannel channel,
  }) {
    final candidates = items.where((item) {
      if (item.platform != platform) {
        return false;
      }
      if (item.shortVersion <= currentBuildNumber) {
        return false;
      }
      if (!channel.includesPrereleases && item.isPrerelease) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => b.shortVersion.compareTo(a.shortVersion));
    return candidates.first;
  }
}

List<AleraUpdateInfo> _itemsFromJson(
  Map<String, Object?> json, {
  required int schemaVersion,
}) {
  final artifacts = json['artifacts'];
  if (schemaVersion >= 2 && artifacts is List && artifacts.isNotEmpty) {
    return [
      for (final artifact in artifacts)
        if (artifact is Map)
          _itemFromJson(json, artifact: Map<String, Object?>.from(artifact)),
    ];
  }
  return [_itemFromJson(json)];
}

AleraUpdateInfo _itemFromJson(
  Map<String, Object?> json, {
  Map<String, Object?>? artifact,
}) {
  final source = artifact ?? json;
  final url = _requiredString(source, 'url');
  final size = _optionalInt(source['size']);
  if (size != null && size <= 0) {
    throw const FormatException('size must be a positive integer.');
  }
  return AleraUpdateInfo(
    version: _requiredString(json, 'version'),
    shortVersion: _requiredInt(json, 'shortVersion'),
    date: _requiredString(json, 'date'),
    mandatory: _requiredBool(json, 'mandatory'),
    url: Uri.parse(url),
    platform: _requiredString(source, 'platform'),
    changes: _changesFromJson(json['changes']),
    installerKind: _optionalString(source['installerKind']) ?? 'directory',
    sha256: _optionalString(source['sha256']),
    size: size,
    signatureBundleUrl: _optionalUri(source['signatureBundleUrl']),
    provenanceUrl: _optionalUri(source['provenanceUrl']),
  );
}

List<String> _changesFromJson(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return [
    for (final change in value)
      if (change is Map)
        if (_optionalString(change['message']) != null)
          _optionalString(change['message'])!,
  ];
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  final parsed = _optionalInt(value);
  if (parsed != null) {
    return parsed;
  }
  throw FormatException('$key must be an integer.');
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

Uri? _optionalUri(Object? value) {
  final raw = _optionalString(value);
  if (raw == null) {
    return null;
  }
  return Uri.parse(raw);
}
