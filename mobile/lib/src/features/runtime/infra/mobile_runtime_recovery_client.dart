import 'dart:convert';

import 'package:alera_mobile/src/core/mobile_protocol.dart';

import '../domain/workspace_creation_result.dart';
import '../domain/workspace_relocation_recovery.dart';
import '../domain/workspace_recovery_client.dart';
import '../domain/workspace_summary.dart';
import 'workspace_buffer_guard_request.dart';

mixin MobileRuntimeRecoveryClient implements WorkspaceRecoveryClient {
  Set<String> get runtimeCapabilities;
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]);

  @override
  bool get supportsWorkspaceRecovery =>
      runtimeCapabilities.contains(sharedCheckoutWorkspacesCapability) &&
      runtimeCapabilities.contains('safeWorkspaceHandoffV1');

  @override
  Future<WorkspaceRelocationRecoverySnapshot> inspectWorkspaceRecovery(
    WorkspaceSummary workspace,
  ) async {
    if (!supportsWorkspaceRecovery) {
      throw UnsupportedError(
        'Update Alera on this host to inspect workspace recovery.',
      );
    }
    final response = await request(
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
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) async {
    final fresh = await inspectWorkspaceRecovery(workspace);
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

  @override
  Future<WorkspaceCreationResult> resumeWorkspaceRecovery(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry, {
    required bool sharedImpactConfirmed,
  }) async {
    final payload = entry.resumePayload(
      sharedImpactConfirmed: sharedImpactConfirmed,
    );
    await _refreshEntry(workspace, entry);
    final response = await requestWithWorkspaceBufferGuard(
      request: request,
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
    final result = WorkspaceCreationResult.fromJson(json);
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

  @override
  Future<void> runWorkspaceRecoverySetup(
    WorkspaceSummary workspace,
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
    await request('workspace.runSetup', {
      'id': workspace.id,
      'relocationId': entry.id,
    }, const Duration(minutes: 30));
  }

  @override
  Future<void> cancelWorkspaceRecoverySetup(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) => _controlSetup(workspace, entry, 'workspace.cancelRelocationSetup');

  @override
  Future<void> recoverWorkspaceSetupOutcome(
    WorkspaceSummary workspace,
    WorkspaceRelocationRecoveryEntry entry,
  ) => _controlSetup(workspace, entry, 'workspace.recoverRelocationSetup');

  Future<void> _controlSetup(
    WorkspaceSummary workspace,
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
    await request(operation, {
      'id': workspace.id,
      'relocationId': entry.id,
      'attemptId': entry.setupAttemptId,
    }, const Duration(minutes: 2));
  }
}
