import 'package:alera/src/features/mcp_access/domain/mcp_access_repository.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/mcp_access/infra/runtime_mcp_access_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mcp_access_providers.g.dart';

@Riverpod(keepAlive: true)
McpAccessRepository mcpAccessRepository(Ref ref) {
  return RuntimeMcpAccessRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

// The settings stream recovers on its own and the grants list has a Refresh
// action, so an automatic retry would only hide a failure behind a spinner.
Duration? _noMcpRetry(int retryCount, Object error) => null;

/// Settings for the open MCP Access pane. Auto-disposed so reopening the pane
/// reads fresh values and the event subscription ends when it closes.
@Riverpod(retry: _noMcpRetry)
class McpAccessSettingsController extends _$McpAccessSettingsController {
  @override
  Stream<McpAccessSettings?> build() {
    return ref.watch(mcpAccessRepositoryProvider).watchSettings();
  }

  Future<void> setAccess(McpAccessLevel access) {
    return _apply(
      () =>
          ref.read(mcpAccessRepositoryProvider).updateSettings(access: access),
    );
  }

  Future<void> rename(String runtimeName) {
    return _apply(
      () => ref
          .read(mcpAccessRepositoryProvider)
          .updateSettings(runtimeName: runtimeName),
    );
  }

  // Publishes the update's own answer at once instead of waiting for the
  // `mcpSettingsChanged` refresh. Failures propagate so the pane can show them
  // inline next to the control that caused them.
  Future<void> _apply(Future<McpAccessSettings> Function() update) async {
    final next = await update();
    if (ref.mounted) {
      state = AsyncData<McpAccessSettings?>(next);
    }
  }
}

/// Grants for the open pane, read again each time the pane is shown.
@Riverpod(retry: _noMcpRetry)
Future<List<McpGrant>> mcpGrants(Ref ref) {
  return ref.watch(mcpAccessRepositoryProvider).listGrants();
}
