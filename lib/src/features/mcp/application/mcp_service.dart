import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/shared/models/contracts.dart';

class McpService {
  McpService(this._client);

  final CodexAppServerClient _client;

  Future<List<McpServerConfig>> listServers() async {
    final response = await _client.mcpServerStatusList();
    final result = response['result'];
    if (result is! Map<String, dynamic>) {
      return const <McpServerConfig>[];
    }

    final data = result['data'];
    if (data is! List) {
      return const <McpServerConfig>[];
    }

    return data.whereType<Map<String, dynamic>>().map((entry) {
      final name = (entry['name'] ?? '').toString();
      return McpServerConfig(
        id: name,
        transport: (entry['transport'] ?? 'stdio').toString(),
        payload: entry,
        enabled: entry['enabled'] as bool? ?? true,
      );
    }).toList(growable: false);
  }

  Future<String> startOauthLogin(String name) async {
    final response = await _client.mcpServerOauthLogin(name);
    final result = response['result'] as Map<String, dynamic>?;
    return (result?['authorizationUrl'] ?? '').toString();
  }

  Future<void> setServerConfig({
    required String serverId,
    required Map<String, dynamic> config,
  }) async {
    await _client.configValueWrite(
      key: 'mcp_servers.$serverId',
      value: config,
    );
  }

  Future<void> removeServerConfig(String serverId) async {
    await _client.configValueWrite(
      key: 'mcp_servers.$serverId',
      value: null,
    );
  }

  Future<void> reloadConfig() async {
    await _client.configMcpServerReload();
  }
}
