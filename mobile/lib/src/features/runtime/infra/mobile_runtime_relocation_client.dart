import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_relocation_client.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

import 'workspace_buffer_guard_request.dart';

mixin MobileRuntimeRelocationClient implements WorkspaceRelocationClient {
  Set<String> get runtimeCapabilities;

  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  @override
  bool get supportsWorkspaceRelocation =>
      runtimeCapabilities.contains(sharedCheckoutWorkspacesCapability) &&
      runtimeCapabilities.contains('safeWorkspaceHandoffV1');

  void _validateRelocation(bool confirmed) {
    if (!supportsWorkspaceRelocation) {
      throw UnsupportedError(
        'Update Alera on this host to relocate workspaces.',
      );
    }
    if (!confirmed) {
      throw StateError(
        'Confirm the impact on all tasks sharing the project folder.',
      );
    }
  }

  @override
  Future<WorkspaceCreationResult> handOffWorkspace({
    required String workspaceId,
    required String relocationId,
    required String branch,
    required bool moveChanges,
    required bool sharedImpactConfirmed,
    String? replacementBranch,
  }) async {
    _validateRelocation(sharedImpactConfirmed);
    final response = await requestWithWorkspaceBufferGuard(
      request: request,
      workspaceId: workspaceId,
      operation: 'handOff',
      payload: {
        'id': workspaceId,
        'relocationId': relocationId,
        'branch': branch,
        'moveChanges': moveChanges,
        'replacementBranch': replacementBranch,
        'reuseExistingBranch': replacementBranch != null,
        'sharedImpactConfirmed': true,
        'deferSetup': true,
      },
      timeout: const Duration(minutes: 30),
    );
    return WorkspaceCreationResult.fromJson(_relocationMap(response));
  }

  @override
  Future<WorkspaceSummary> handOnWorkspace({
    required String workspaceId,
    required String relocationId,
    required bool sharedImpactConfirmed,
  }) async {
    _validateRelocation(sharedImpactConfirmed);
    final response = _relocationMap(
      await requestWithWorkspaceBufferGuard(
        request: request,
        workspaceId: workspaceId,
        operation: 'handOn',
        payload: {
          'id': workspaceId,
          'relocationId': relocationId,
          'sharedImpactConfirmed': true,
        },
        timeout: const Duration(minutes: 10),
      ),
    );
    return WorkspaceSummary.fromJson(_relocationMap(response['workspace']));
  }
}

Map<String, Object?> _relocationMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid relocation response.');
  }
  return Map<String, Object?>.from(value);
}
