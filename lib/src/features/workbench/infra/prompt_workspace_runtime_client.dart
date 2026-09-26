import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class const GeneratedWorkspaceIdentity({
  required final String workspaceName,
  required final String branchName,
  final String? sectionId,
});

class const AgentProfileLaunchResult({
  required final String tabId,
  required final String agentType,
  required final String profileId,
  required final bool idempotent,
});

class const NonIdempotentAgentLaunchFailure(final Object cause)
    implements Exception {
  @override
  String toString() => cause.toString();
}

class PromptWorkspaceRuntimeClient(
  final RuntimeHostClient _client, {
  final Future<void> Function()? beforeAccess,
}) {
  Future<GeneratedWorkspaceIdentity> generateIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
    String? tabId,
    bool autoAssignSection = false,
  }) async {
    await beforeAccess?.call();
    final payload = _asMap(
      await _client.runtimeRequest(
        'aiText.workspaceIdentity.generate',
        <String, Object?>{
          'operationId': operationId,
          'projectId': projectId,
          'prompt': prompt,
          'tabId': ?tabId,
          // Additive: an older host ignores the flag and simply omits
          // sectionId from the response.
          'autoAssignSection': autoAssignSection,
        },
        const Duration(minutes: 11),
      ),
    );
    return GeneratedWorkspaceIdentity(
      workspaceName: _requiredString(payload, 'workspaceName'),
      branchName: _requiredString(payload, 'branchName'),
      sectionId: _optionalString(payload, 'sectionId'),
    );
  }

  Future<void> cancel(String operationId) async {
    await beforeAccess?.call();
    await _client.runtimeRequest('aiText.cancel', <String, Object?>{
      'operationId': operationId,
    });
  }

  Future<AgentProfileLaunchResult> launchAgent({
    required String workspaceId,
    required String profileId,
    String prompt = '',
    String? resumeSessionId,
    required String clientMutationId,
    required bool requireIdempotency,
  }) async {
    await beforeAccess?.call();
    if (resumeSessionId != null && !await supportsSessionResume()) {
      throw StateError(
        'This runtime does not support resuming agent sessions.',
      );
    }
    final requestPayload = <String, Object?>{
      'workspaceId': workspaceId,
      'profileId': profileId,
      'prompt': prompt,
      'resumeSessionId': ?resumeSessionId?.trim(),
      'clientMutationId': clientMutationId,
    };
    Object? response;
    var idempotent = true;
    try {
      response = await _client.runtimeRequest(
        'agentProfile.launchIdempotent',
        requestPayload,
      );
    } on StateError catch (error) {
      if (requireIdempotency ||
          resumeSessionId != null ||
          error.message !=
              'Unknown terminal host request: agentProfile.launchIdempotent') {
        rethrow;
      }
      idempotent = false;
      try {
        response = await _client.runtimeRequest(
          'agentProfile.launch',
          requestPayload,
        );
      } on Object catch (legacyError, stackTrace) {
        Error.throwWithStackTrace(
          NonIdempotentAgentLaunchFailure(legacyError),
          stackTrace,
        );
      }
    }
    final payload = _asMap(response);
    final tab = _asMap(payload['tab']);
    return AgentProfileLaunchResult(
      tabId: _requiredString(tab, 'id'),
      agentType: _requiredString(payload, 'agentType'),
      profileId: _requiredString(payload, 'profileId'),
      idempotent: idempotent,
    );
  }

  Future<bool> supportsIdempotentAgentLaunch() async {
    await beforeAccess?.call();
    final status = _asMap(await _client.runtimeRequest('status.get'));
    final capabilities = status['runtimeCapabilities'];
    return capabilities is List &&
        capabilities.contains(
          aleraRuntimeHostAgentProfileLaunchIdempotencyCapability,
        );
  }

  Future<bool> supportsSessionResume() async {
    await beforeAccess?.call();
    final status = _asMap(await _client.runtimeRequest('status.get'));
    final capabilities = status['runtimeCapabilities'];
    return capabilities is List &&
        capabilities.contains(
          aleraRuntimeHostAgentProfileSessionResumeCapability,
        );
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException('Runtime response must be a JSON object.');
}

String _requiredString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is String && field.trim().isNotEmpty) {
    return field;
  }
  throw FormatException('Runtime response is missing "$key".');
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is String && field.trim().isNotEmpty) {
    return field;
  }
  return null;
}
