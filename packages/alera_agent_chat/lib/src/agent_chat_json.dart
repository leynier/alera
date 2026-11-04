typedef AgentChatJson = Map<String, Object?>;

/// A JSON object with string keys; anything else reads as empty so a malformed
/// field degrades to "absent" instead of throwing in a render path.
AgentChatJson agentChatJsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, Object?>{};
}

List<Object?> agentChatJsonList(Object? value) =>
    value is List ? value : const <Object?>[];

String? agentChatJsonString(Object? value) {
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value;
}

String agentChatJsonText(Object? value) => value is String ? value : '';

int? agentChatJsonInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? agentChatJsonDouble(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool agentChatJsonBool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

DateTime? agentChatJsonDate(Object? value) {
  final text = agentChatJsonString(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}

List<String> agentChatJsonStringList(Object? value) => <String>[
  for (final item in agentChatJsonList(value))
    if (item is String && item.trim().isNotEmpty) item,
];

/// Wire enums arrive as snake_case, camelCase or kebab-case depending on the
/// Rust serde attribute of the type that produced them; comparing a folded
/// token keeps every spelling equivalent.
String agentChatWireToken(Object? value) => value is String
    ? value.replaceAll('_', '').replaceAll('-', '').toLowerCase()
    : '';

T agentChatWireEnum<T extends Enum>(Object? value, List<T> values, T fallback) {
  final token = agentChatWireToken(value);
  if (token.isEmpty) return fallback;
  for (final candidate in values) {
    if (candidate.name.toLowerCase() == token) return candidate;
  }
  return fallback;
}
