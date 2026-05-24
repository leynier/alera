import 'dart:convert';

import 'package:alera/src/features/updater/domain/alera_update.dart';

class AleraUpdateArchive {
  const AleraUpdateArchive({required this.appName, required this.items});

  factory AleraUpdateArchive.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Update archive must be a JSON object.');
    }
    return AleraUpdateArchive.fromJson(Map<String, Object?>.from(decoded));
  }

  factory AleraUpdateArchive.fromJson(Map<String, Object?> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Update archive must contain items.');
    }
    return AleraUpdateArchive(
      appName: _optionalString(json['appName']) ?? 'Alera',
      items: [
        for (final item in items)
          if (item is Map) _itemFromJson(Map<String, Object?>.from(item)),
      ],
    );
  }

  final String appName;
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

AleraUpdateInfo _itemFromJson(Map<String, Object?> json) {
  return AleraUpdateInfo(
    version: _requiredString(json, 'version'),
    shortVersion: _requiredInt(json, 'shortVersion'),
    date: _requiredString(json, 'date'),
    mandatory: _requiredBool(json, 'mandatory'),
    url: Uri.parse(_requiredString(json, 'url')),
    platform: _requiredString(json, 'platform'),
    changes: _changesFromJson(json['changes']),
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
  if (value is int) {
    return value;
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('$key must be an integer.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}
