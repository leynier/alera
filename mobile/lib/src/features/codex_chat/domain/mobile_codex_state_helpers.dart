part of 'mobile_codex_state.dart';

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _maps(Object? value) => value is List
    ? <Map<String, Object?>>[
        for (final item in value)
          if (item is Map) _map(item),
      ]
    : const <Map<String, Object?>>[];

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _first(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return '';
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

DateTime? _dateTime(Object? value) =>
    value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');

bool _containsFast(Object? value) {
  if (value is String) return value.trim().toLowerCase() == 'fast';
  if (value is Map) {
    if (<Object?>[
      value['id'],
      value['name'],
      value['tier'],
      value['slug'],
      value['serviceTier'],
    ].whereType<String>().any(
      (entry) => entry.trim().toLowerCase() == 'fast',
    )) {
      return true;
    }
    return value.values.any(_containsFast);
  }
  if (value is Iterable) return value.any(_containsFast);
  return false;
}

List<String> _reasoningEfforts(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final entry in value) {
    final effort = entry is Map
        ? (entry['reasoningEffort'] ??
                  entry['effort'] ??
                  entry['id'] ??
                  entry['name'])
              ?.toString()
        : entry.toString();
    if (effort != null && effort.trim().isNotEmpty) result.add(effort.trim());
  }
  return result;
}

String _safeMarkdown(String value) => value.replaceAll(
  RegExp(r'\[([^\]]+)\]\(streamdown:incomplete-link\)'),
  r'\$1',
);
