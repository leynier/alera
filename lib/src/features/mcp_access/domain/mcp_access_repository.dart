import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';

/// Runtime-side MCP Control settings and the MCP clients granted access.
abstract interface class McpAccessRepository {
  /// Emits the current settings and refreshes on `mcpSettingsChanged`. Emits
  /// `null` when the connected runtime predates MCP Control.
  Stream<McpAccessSettings?> watchSettings();

  /// Sends only the fields that are set. Renaming fails with the cloud's error
  /// when the name is already taken in the account.
  Future<McpAccessSettings> updateSettings({
    McpAccessLevel? access,
    String? runtimeName,
  });

  Future<List<McpGrant>> listGrants();

  Future<void> revokeGrant(String grantId);
}
