import 'dart:async';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'dart:convert';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/prompt_image_upload.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:logging/logging.dart';

// Managed workspace lifecycle mirrors the desktop client timeouts
// (lib/src/features/workbench/infra/runtime_managed_workspace_client.dart).
const Duration _managedWorkspaceCreateTimeout = Duration(minutes: 30);
const Duration _managedWorkspaceRemoveTimeout = Duration(minutes: 10);

mixin MobileRuntimeWorkspaceClient {
  Set<String> get runtimeCapabilities;

  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]);

  bool get supportsAgentTitles =>
      runtimeCapabilities.contains(aiAssistAgentTitleCapability);

  Future<void> generateAgentTitle(WorkspaceTabSummary tab) async {
    await request('aiText.agentTitle.generate', <String, Object?>{
      'tabId': tab.id,
      'expectedConversationId': tab.payload['agentTitleConversationId'],
      'expectedRevision': tab.payload['agentTitleRevision'],
    }, const Duration(minutes: 11));
  }

  bool get supportsWorkspaceMutations =>
      runtimeCapabilities.contains(mobileWorkspaceMutationsCapability);

  bool get supportsPromptWorkspaceCreation =>
      runtimeCapabilities.contains(aiAssistWorkspaceIdentityCapability) &&
      runtimeCapabilities.contains(agentProfilePromptLaunchCapability);

  bool get supportsIdempotentAgentProfileLaunch =>
      runtimeCapabilities.contains(agentProfileLaunchIdempotencyCapability);

  bool get supportsPromptImageUpload =>
      runtimeCapabilities.contains(mobilePromptImageUploadCapability);

  bool get supportsSpeechMessageProcessing =>
      runtimeCapabilities.contains(aiAssistSpeechMessageCapability);

  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    await request('workspace.setPinned', <String, Object?>{
      'id': workspaceId,
      'isPinned': isPinned,
    });
  }

  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await request('workspaceRelation.link', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await request('workspaceRelation.unlink', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) async {
    final payload = await requestMap(
      'workspace.createManaged',
      <String, Object?>{
        'projectId': projectId,
        'branch': branch,
        'reuseExistingBranch': reuseExistingBranch,
        if (!reuseExistingBranch && sourceBranch != null)
          'sourceBranch': sourceBranch,
        'name': ?name,
        'parentWorkspaceId': ?parentWorkspaceId,
        // Older hosts ignore this and keep running setup inline. Newer hosts
        // return a portable command that mobile starts in a Setup terminal.
        'deferSetup': true,
      },
      _managedWorkspaceCreateTimeout,
    );
    return WorkspaceCreationResult.fromJson(payload);
  }

  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    await request('workspace.removeManaged', <String, Object?>{
      'id': workspaceId,
      'deleteBranch': ?deleteBranch,
    }, _managedWorkspaceRemoveTimeout);
  }

  Future<List<String>> cascadePreview(String workspaceId) async {
    final payload = await requestMap(
      'workspaceCascade.preview',
      <String, Object?>{
        'workspaceIds': <String>[workspaceId],
        'includeDescendants': true,
      },
    );
    return payload.stringList('workspaceIds');
  }

  Future<void> removeTab(String tabId) async {
    await request('tab.remove', <String, Object?>{'id': tabId});
  }

  Future<List<ProjectSummary>> listProjects() async {
    final payload = await requestList('project.list');
    return <ProjectSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          ProjectSummary.fromJson(asJsonMap(item)),
    ];
  }

  Future<ProjectBranches> listBranches(String projectId) async {
    final payload = await requestMap('project.branches.list', <String, Object?>{
      'projectId': projectId,
    });
    return ProjectBranches.fromJson(payload);
  }

  Future<List<AgentProfileSummary>> listAgentProfiles() async {
    final payload = await requestMap('agentProfile.list');
    final items = payload['items'];
    if (items is! List) {
      return const <AgentProfileSummary>[];
    }
    return <AgentProfileSummary>[
      for (final item in items)
        if (item is Map)
          AgentProfileSummary.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Future<GeneratedWorkspaceIdentity> generateWorkspaceIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
  }) async {
    final payload = await requestMap(
      'aiText.workspaceIdentity.generate',
      <String, Object?>{
        'operationId': operationId,
        'projectId': projectId,
        'prompt': prompt,
      },
      const Duration(minutes: 11),
    );
    return GeneratedWorkspaceIdentity(
      workspaceName: payload.requiredString('workspaceName'),
      branchName: payload.requiredString('branchName'),
    );
  }

  Future<void> cancelWorkspaceIdentity(String operationId) async {
    await request('aiText.cancel', <String, Object?>{
      'operationId': operationId,
    });
  }

  Future<Map<String, Object?>> processSpeechMessage({
    required String operationId,
    required String text,
    required String mode,
    String? workspaceId,
    String? tabId,
  }) async {
    if (!supportsSpeechMessageProcessing) {
      throw UnsupportedError(
        'Update Alera on the paired host to process speech messages.',
      );
    }
    return requestMap('aiText.speechMessage.generate', <String, Object?>{
      'operationId': operationId,
      'text': text,
      'mode': mode,
      'workspaceId': ?workspaceId,
      'tabId': ?tabId,
    }, const Duration(minutes: 3));
  }

  Future<PromptImageUploadResult> uploadPromptImage({
    required String format,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    if (!supportsPromptImageUpload) {
      throw UnsupportedError(
        'Update Alera on this host to add images to a prompt.',
      );
    }
    if (sizeBytes <= 0) {
      throw StateError('The selected image is empty.');
    }
    if (sizeBytes > maxPromptImageBytes) {
      throw StateError('The selected image is larger than the 18 MiB limit.');
    }

    String? uploadId;
    try {
      final started = await requestMap(
        'mobile.promptImage.start',
        <String, Object?>{'format': format, 'sizeBytes': sizeBytes},
      );
      uploadId = started.requiredString('uploadId');
      var offset = 0;
      await for (final bytes in openRead()) {
        for (var start = 0; start < bytes.length;) {
          final end = start + maxPromptImageChunkBytes < bytes.length
              ? start + maxPromptImageChunkBytes
              : bytes.length;
          final chunk = bytes.sublist(start, end);
          final response = await requestMap(
            'mobile.promptImage.chunk',
            <String, Object?>{
              'uploadId': uploadId,
              'offset': offset,
              'dataBase64': base64Encode(chunk),
            },
          );
          final nextOffset = response['nextOffset'];
          final expectedOffset = offset + chunk.length;
          if (nextOffset is! int || nextOffset != expectedOffset) {
            throw StateError(
              'The host returned an invalid image upload offset.',
            );
          }
          offset = nextOffset;
          start = end;
        }
      }
      if (offset != sizeBytes) {
        throw StateError('The selected image could not be read completely.');
      }
      final completed = await requestMap(
        'mobile.promptImage.complete',
        <String, Object?>{'uploadId': uploadId},
      );
      return PromptImageUploadResult.fromJson(completed);
    } on Object {
      final failedUploadId = uploadId;
      if (failedUploadId != null) {
        try {
          await request('mobile.promptImage.cancel', <String, Object?>{
            'uploadId': failedUploadId,
          });
        } on Object catch (cancelError, cancelStackTrace) {
          // The original upload error is more useful to the user, but a failed
          // cleanup must remain visible in diagnostics instead of disappearing.
          Logger('MobileRuntimeWorkspaceClient').warning(
            'could not cancel failed prompt image upload',
            cancelError,
            cancelStackTrace,
          );
        }
      }
      rethrow;
    }
  }

  Future<AgentProfileLaunchResult> launchAgentProfile({
    required String workspaceId,
    required String profileId,
    required String prompt,
    required String clientMutationId,
  }) async {
    final requestType = supportsIdempotentAgentProfileLaunch
        ? 'agentProfile.launchIdempotent'
        : 'agentProfile.launch';
    final payload = await requestMap(requestType, <String, Object?>{
      'workspaceId': workspaceId,
      'profileId': profileId,
      'prompt': prompt,
      // An older host ignores this additive field. It receives the legacy
      // verb only when the current connection did not negotiate idempotency.
      'clientMutationId': clientMutationId,
    });
    final tab = payload.mapValue('tab');
    return AgentProfileLaunchResult(
      tabId: tab.requiredString('id'),
      agentType: payload.requiredString('agentType'),
    );
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final payload = await requestList('workspace.listAll');
    return <WorkspaceSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          WorkspaceSummary.fromJson(asJsonMap(item)),
    ];
  }
}
