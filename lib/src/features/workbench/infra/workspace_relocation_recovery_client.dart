import 'dart:convert';

import '../domain/workspace_creation_result.dart';
import 'runtime_managed_workspace_client.dart';
import 'workspace_buffer_guard_request.dart';
import '../domain/workspace.dart';
import '../domain/workspace_relocation_recovery.dart';
import 'terminal_host/terminal_host_protocol.dart';

class WorkspaceRelocationRecoveryClient(
  final RuntimeHostClient client, {
  final Future<void> Function()? beforeAccess,
}) {
  Future<WorkspaceRelocationRecoverySnapshot> inspect(
    Workspace workspace,
  ) async {
    await beforeAccess?.call();
    final status = await client.runtimeRequest('status.get');
    final capabilities = status is Map ? status['runtimeCapabilities'] : null;
    if (capabilities is! List ||
        !capabilities.contains(aleraRuntimeHostSharedCheckoutCapability) ||
        !capabilities.contains(aleraRuntimeHostSafeHandoffCapability)) {
      throw UnsupportedError(
        'Update Alera on this host to inspect workspace recovery.',
      );
    }
    final response = await client.runtimeRequest(
      workspace.isRemote
          ? 'workspace.sshRelocationRecovery'
          : 'workspace.relocationRecovery',
      {'id': workspace.id, 'limit': 20},
      const Duration(seconds: 45),
    );
    return WorkspaceRelocationRecoverySnapshot.fromResponse(
      workspace,
      response,
    );
  }

  Future<WorkspaceRelocationRecoveryEntry> _refreshEntry(
    Workspace workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) async {
    final fresh = await inspect(workspace);
    final latest = fresh.entries.firstOrNull;
    if (latest == null ||
        latest.id != entry.id ||
        jsonEncode(latest.resumePayload(sharedImpactConfirmed: true)) !=
            jsonEncode(entry.resumePayload(sharedImpactConfirmed: true))) {
      throw StateError(
        'This transfer was superseded or its saved choices changed. Refresh recovery before continuing.',
      );
    }
    return latest;
  }

  Future<WorkspaceCreationResult> resume(
    Workspace workspace,
    WorkspaceRelocationRecoveryEntry entry, {
    required bool sharedImpactConfirmed,
  }) async {
    final payload = entry.resumePayload(
      sharedImpactConfirmed: sharedImpactConfirmed,
    );
    await _refreshEntry(workspace, entry);
    final response = await requestWithWorkspaceBufferGuard(
      request: client.runtimeRequest,
      workspaceId: workspace.id,
      operation: entry.toProjectCheckout ? 'handOn' : 'handOff',
      payload: payload,
      timeout: const Duration(minutes: 30),
    );
    if (response is! Map) {
      throw const FormatException('Invalid relocation result.');
    }
    final json = Map<String, Object?>.from(response);
    if (entry.toProjectCheckout) json['setupReport'] = {'steps': <Object?>[]};
    final result = workspaceCreationResultFromRuntime(json);
    if (result.workspace.id != workspace.id ||
        result.workspace.instanceId != workspace.instanceId ||
        result.workspace.projectId != workspace.projectId ||
        result.workspace.hostId != workspace.hostId) {
      throw const FormatException(
        'Relocation returned a different task instance.',
      );
    }
    return result;
  }

  Future<void> runSetup(
    Workspace workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) async {
    final fresh = await _refreshEntry(workspace, entry);
    if (!fresh.completed ||
        !fresh.hasSetupRecipe ||
        fresh.setupFinished ||
        fresh.setupAttemptId != null) {
      throw StateError(
        'Setup has already been attempted or the transfer is not complete. Refresh its outcome before continuing.',
      );
    }
    await client.runtimeRequest('workspace.runSetup', {
      'id': workspace.id,
      'relocationId': entry.id,
    }, const Duration(minutes: 30));
  }

  Future<void> cancelSetup(
    Workspace workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) => _controlSetup(workspace, entry, 'workspace.cancelRelocationSetup');

  Future<void> recoverSetup(
    Workspace workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) => _controlSetup(workspace, entry, 'workspace.recoverRelocationSetup');

  Future<void> _controlSetup(
    Workspace workspace,
    WorkspaceRelocationRecoveryEntry entry,
    String operation,
  ) async {
    final fresh = await _refreshEntry(workspace, entry);
    if (!fresh.completed ||
        entry.setupAttemptId == null ||
        fresh.setupAttemptId != entry.setupAttemptId ||
        fresh.setupFinished) {
      throw StateError(
        'Setup attempt or outcome changed. Refresh recovery before continuing.',
      );
    }
    await client.runtimeRequest(operation, {
      'id': workspace.id,
      'relocationId': entry.id,
      'attemptId': entry.setupAttemptId,
    }, const Duration(minutes: 2));
  }
}
