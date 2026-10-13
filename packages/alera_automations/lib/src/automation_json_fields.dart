typedef JsonMap = Map<String, Object?>;

JsonMap automationJsonMap(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return <String, Object?>{};
}

List<Object?> automationJsonList(Object? value) =>
    value is List ? value : const <Object?>[];

String automationJsonString(Object? value) =>
    value is String ? value : value?.toString() ?? '';

String? automationJsonOptionalString(Object? value) {
  final result = automationJsonString(value).trim();
  return result.isEmpty ? null : result;
}

int automationJsonInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(automationJsonString(value)) ?? fallback;
}

int? automationJsonOptionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(automationJsonString(value));
}

DateTime? automationJsonDate(Object? value) {
  final text = automationJsonOptionalString(value);
  return text == null ? null : DateTime.tryParse(text);
}

List<String> automationJsonStringList(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.trim().isNotEmpty).toList()
    : const <String>[];
