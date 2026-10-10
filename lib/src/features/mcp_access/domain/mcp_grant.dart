/// OAuth scope that unlocks administrative MCP tools.
const String mcpAdminScope = 'mcp:admin';

/// An MCP client the user authorized through the consent page, as returned by
/// `mcp.grants.list`.
final class const McpGrant({
  required final String id,
  required final String clientId,
  required final String clientName,
  required final List<String> scopes,
  required final bool allRuntimes,
  required final List<String> runtimeIds,
  final String? redirectHost,
  final DateTime? createdAt,
  final DateTime? lastUsedAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('MCP grant id must be a non-empty string.');
    }
    final clientId = _optionalString(json['clientId']) ?? '';
    return McpGrant(
      id: id,
      clientId: clientId,
      clientName:
          _optionalString(json['clientName']) ??
          (clientId.isEmpty ? 'Unknown App' : clientId),
      redirectHost: _optionalString(json['redirectHost']),
      scopes: _strings(json['scopes']),
      allRuntimes: json['allRuntimes'] == true,
      runtimeIds: _strings(json['runtimeIds']),
      createdAt: _optionalDateTime(json['createdAt']),
      lastUsedAt: _optionalDateTime(json['lastUsedAt']),
    );
  }

  /// Whether the grant may run execute tools, not only read ones.
  bool get canExecute => scopes.contains('mcp:execute');

  /// Whether the user allowed this app's administrative tools at consent.
  bool get canAdmin => scopes.contains(mcpAdminScope);
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return List<String>.unmodifiable(<String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item,
  ]);
}

// The cloud sends ISO-8601 strings; epoch numbers are accepted defensively so a
// payload change degrades to a readable date instead of a parse failure.
DateTime? _optionalDateTime(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc();
  }
  if (value is num) {
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
  }
  return null;
}
