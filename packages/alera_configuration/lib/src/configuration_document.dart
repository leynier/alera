import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef JsonMap = Map<String, Object?>;
const configurationMaxBytes = 512 * 1024;

JsonMap jsonMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

Object? canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: canonicalJson(value[key]),
    };
  }
  if (value is List) return value.map(canonicalJson).toList();
  return value;
}

bool sameJson(Object? a, Object? b) =>
    jsonEncode(canonicalJson(a)) == jsonEncode(canonicalJson(b));
String configurationDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(canonicalJson(value)))).toString();

class ConfigurationDocument {
  ConfigurationDocument(JsonMap json)
    : json = jsonMap(jsonDecode(jsonEncode(json))) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException(
        'Update Alera to read this configuration format.',
      );
    }
    for (final block in ['shared', 'desktop', 'mobile']) {
      if (json[block] is! Map)
        throw FormatException('Invalid $block configuration.');
    }
    if (utf8.encode(jsonEncode(json)).length > configurationMaxBytes) {
      throw const FormatException('Configuration exceeds 512 KiB.');
    }
  }
  factory ConfigurationDocument.empty() => ConfigurationDocument({
    'schemaVersion': 1,
    'shared': <String, Object?>{},
    'desktop': <String, Object?>{},
    'mobile': <String, Object?>{},
  });
  final JsonMap json;
  String get digest => configurationDigest(json);
  ConfigurationDocument withBlocks(JsonMap blocks) =>
      ConfigurationDocument({...json, ...blocks});
}

class ConfigurationRevision {
  ConfigurationRevision({
    required this.revision,
    required this.document,
    this.deviceName = '',
    this.createdAt = '',
    this.summary = '',
  });
  factory ConfigurationRevision.fromJson(JsonMap value) =>
      ConfigurationRevision(
        revision: value['revision'] as int,
        document: ConfigurationDocument(jsonMap(value['document'])),
        deviceName: value['deviceName'] as String? ?? '',
        createdAt: value['createdAt'] as String? ?? '',
        summary: value['summary'] as String? ?? '',
      );
  final int revision;
  final ConfigurationDocument document;
  final String deviceName;
  final String createdAt;
  final String summary;
  JsonMap toJson() => {
    'revision': revision,
    'document': document.json,
    'deviceName': deviceName,
    'createdAt': createdAt,
    'summary': summary,
  };
}
