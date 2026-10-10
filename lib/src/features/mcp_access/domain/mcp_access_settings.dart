/// Public remote MCP endpoint served by the Alera edge (see
/// `docs/remote-mcp.md`). MCP clients connect here, not to the runtime.
const String aleraRemoteMcpEndpoint = 'https://api.alera.build/v1/mcp';

/// Per-runtime MCP Control level, ordered `off` < `read` < `full` < `admin`.
/// `off` is the default and what an unknown wire value falls back to, so a
/// malformed payload never widens access.
enum McpAccessLevel(final String wireName, final String label) {
  off('off', 'Off'),
  read('read', 'Read Only'),
  full('full', 'Full Control'),
  admin('admin', 'Admin');

  static McpAccessLevel fromWire(Object? value) {
    for (final level in values) {
      if (level.wireName == value) {
        return level;
      }
    }
    return McpAccessLevel.off;
  }
}

/// Health of the runtime's cloud link, shared by Remote Access and MCP Control.
enum McpRelayState {
  connected,
  connecting,
  retrying,
  blocked,
  disabled,
  unknown;

  static McpRelayState fromWire(Object? value) {
    return switch (value) {
      'connected' => McpRelayState.connected,
      'connecting' => McpRelayState.connecting,
      'retrying' => McpRelayState.retrying,
      'blocked' => McpRelayState.blocked,
      'disabled' => McpRelayState.disabled,
      _ => McpRelayState.unknown,
    };
  }
}

final class const McpRelayStatus({
  final McpRelayState state = McpRelayState.unknown,
  final String? lastError,
}) {
  factory fromJson(Object? json) {
    if (json is! Map) {
      return const McpRelayStatus();
    }
    final lastError = json['lastError'];
    return McpRelayStatus(
      state: McpRelayState.fromWire(json['state']),
      lastError: lastError is String && lastError.trim().isNotEmpty
          ? lastError.trim()
          : null,
    );
  }
}

/// Result of `mcp.settings.get` and `mcp.settings.update`.
final class const McpAccessSettings({
  required final McpAccessLevel access,
  required final String effectiveRuntimeName,
  required final bool accountConnected,
  final String? runtimeName,
  final McpRelayStatus relay = const McpRelayStatus(),
}) {
  factory fromJson(Map<String, Object?> json) {
    final effectiveName = json['effectiveRuntimeName'];
    if (effectiveName is! String) {
      throw const FormatException('MCP settings payload is malformed.');
    }
    final runtimeName = json['runtimeName'];
    return McpAccessSettings(
      access: McpAccessLevel.fromWire(json['access']),
      runtimeName: runtimeName is String && runtimeName.trim().isNotEmpty
          ? runtimeName
          : null,
      effectiveRuntimeName: effectiveName,
      accountConnected: json['accountConnected'] == true,
      relay: McpRelayStatus.fromJson(json['relay']),
    );
  }
}
