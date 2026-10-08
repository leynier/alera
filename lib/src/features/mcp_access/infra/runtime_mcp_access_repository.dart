import 'package:alera/src/features/mcp_access/domain/mcp_access_error_message.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_repository.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

// Account changes are included because `accountConnected` and the relay state
// both follow sign-in, and the host may not re-broadcast MCP settings for it.
const Set<String> _mcpSettingsEventNames = <String>{
  'mcpSettingsChanged',
  'aleraAccountChanged',
  'mobileRelayChanged',
};

final class RuntimeMcpAccessRepository(
  final RuntimeHostClient _client, {
  RuntimeChangeCoalescer? coalescer,
}) implements McpAccessRepository {
  this : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeChangeCoalescer _coalescer;

  Future<McpAccessSettings?> _readSettingsOrUnsupported() async {
    try {
      final payload = await _client.runtimeRequest('mcp.settings.get');
      return McpAccessSettings.fromJson(_map(payload, 'MCP settings'));
    } on StateError catch (error) {
      if (isUnsupportedMcpRequest(error)) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Stream<McpAccessSettings?> watchSettings() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: _mcpSettingsEventNames,
      readSnapshot: _readSettingsOrUnsupported,
      coalesceKey: 'mcpAccessSettings',
      coalescer: _coalescer,
    );
  }

  @override
  Future<McpAccessSettings> updateSettings({
    McpAccessLevel? access,
    String? runtimeName,
  }) async {
    final payload = await _client.runtimeRequest(
      'mcp.settings.update',
      <String, Object?>{
        'access': ?access?.wireName,
        'runtimeName': ?runtimeName,
      },
    );
    return McpAccessSettings.fromJson(_map(payload, 'MCP settings'));
  }

  @override
  Future<List<McpGrant>> listGrants() async {
    final payload = _map(
      await _client.runtimeRequest('mcp.grants.list'),
      'MCP grants',
    );
    final grants = payload['grants'];
    return List<McpGrant>.unmodifiable(<McpGrant>[
      if (grants is List)
        for (final grant in grants)
          if (grant is Map) McpGrant.fromJson(Map<String, Object?>.from(grant)),
    ]);
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    await _client.runtimeRequest('mcp.grants.revoke', <String, Object?>{
      'grantId': grantId,
    });
  }
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw FormatException('Runtime $label payload must be a JSON object.');
}
