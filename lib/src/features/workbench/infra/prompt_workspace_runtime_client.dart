import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class GeneratedWorkspaceIdentity {
  const GeneratedWorkspaceIdentity({
    required this.workspaceName,
    required this.branchName,
  });

  final String workspaceName;
  final String branchName;
}

class AgentProfileLaunchResult {
  const AgentProfileLaunchResult({
    required this.tabId,
    required this.agentType,
    required this.profileId,
    required this.idempotent,
  });

  final String tabId;
  final String agentType;
  final String profileId;
  final bool idempotent;
}

class NonIdempotentAgentLaunchFailure implements Exception {
  const NonIdempotentAgentLaunchFailure(this.cause);

  final Object cause;

  @override
  String toString() => cause.toString();
}

class PromptWorkspaceRuntimeClient {
  PromptWorkspaceRuntimeClient(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

  Future<GeneratedWorkspaceIdentity> generateIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
  }) async {
    await beforeAccess?.call();
    final payload = _asMap(
      await _client.runtimeRequest(
        'aiText.workspaceIdentity.generate',
        <String, Object?>{
          'operationId': operationId,
          'projectId': projectId,
          'prompt': prompt,
        },
        const Duration(minutes: 11),
      ),
    );
    return GeneratedWorkspaceIdentity(
      workspaceName: _requiredString(payload, 'workspaceName'),
      branchName: _requiredString(payload, 'branchName'),
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
    required String prompt,
    required String clientMutationId,
    required bool requireIdempotency,
  }) async {
    await beforeAccess?.call();
    final requestPayload = <String, Object?>{
      'workspaceId': workspaceId,
      'profileId': profileId,
      'prompt': prompt,
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
