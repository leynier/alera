import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class CodexChatHostClient {
  CodexChatHostClient(this._client);

  final RuntimeHostClient _client;

  Stream<RuntimeHostEvent> get events => _client.runtimeEvents;

  Future<Map<String, Object?>> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final value = await _client.runtimeRequest(type, payload);
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw const FormatException('Codex host response must be an object.');
  }

  Future<Map<String, Object?>> openThread(String tabId) {
    return request('codex.thread.open', <String, Object?>{'tabId': tabId});
  }

  Future<Map<String, Object?>> snapshot(String tabId) {
    return request('codex.thread.snapshot', <String, Object?>{'tabId': tabId});
  }

  Future<Map<String, Object?>> listModels() => request('codex.model.list');

  Future<Map<String, Object?>> listCollaborationModes() =>
      request('codex.collaborationModes.list');

  Future<Map<String, Object?>> listSkills(String tabId) =>
      request('codex.skills.list', <String, Object?>{'tabId': tabId});

  Future<Map<String, Object?>> listApps(String tabId) =>
      request('codex.apps.list', <String, Object?>{'tabId': tabId});

  Future<Map<String, Object?>> startTurn(
    String tabId,
    List<Map<String, Object?>> input, {
    String? model,
    required String reasoningEffort,
    required String speedMode,
    required String permissionMode,
    required bool planMode,
    String? collaborationMode,
  }) {
    return request('codex.turn.start', <String, Object?>{
      'tabId': tabId,
      'input': input,
      if (model != null && model.isNotEmpty) 'model': model,
      'reasoning': <String, Object?>{'effort': reasoningEffort},
      'effort': reasoningEffort,
      'serviceTier': speedMode == 'fast' ? 'fast' : null,
      'approvalPolicy': permissionMode,
      if (planMode || collaborationMode != null)
        'collaborationMode': <String, Object?>{
          'mode': collaborationMode ?? 'plan',
          'settings': <String, Object?>{
            if (model != null && model.isNotEmpty) 'model': model,
            'reasoning_effort': reasoningEffort,
          },
        },
    });
  }

  Future<Map<String, Object?>> interrupt(String tabId, String? turnId) {
    return request('codex.turn.interrupt', <String, Object?>{
      'tabId': tabId,
      'turnId': ?turnId,
    });
  }

  Future<Map<String, Object?>> steer(
    String tabId,
    String turnId,
    List<Map<String, Object?>> input,
  ) {
    return request('codex.turn.steer', <String, Object?>{
      'tabId': tabId,
      'turnId': turnId,
      'input': input,
    });
  }

  Future<Map<String, Object?>> rename(String tabId, String name) {
    return request('codex.thread.rename', <String, Object?>{
      'tabId': tabId,
      'name': name,
    });
  }

  Future<Map<String, Object?>> compact(String tabId) {
    return request('codex.thread.compact', <String, Object?>{'tabId': tabId});
  }

  Future<Map<String, Object?>> review(
    String tabId, {
    String target = 'uncommittedChanges',
    String? argument,
    String? delivery,
  }) {
    final targetPayload = <String, Object?>{'type': target};
    if (argument != null && argument.trim().isNotEmpty) {
      final key = switch (target) {
        'baseBranch' => 'branch',
        'commit' => 'sha',
        'custom' => 'instructions',
        _ => null,
      };
      if (key != null) targetPayload[key] = argument.trim();
    }
    return request('codex.review.start', <String, Object?>{
      'tabId': tabId,
      'target': targetPayload,
      if (delivery != null && delivery.isNotEmpty) 'delivery': delivery,
    });
  }

  Future<void> respond(
    Object requestId, {
    Object? result,
    Object? error,
  }) async {
    await request('codex.response', <String, Object?>{
      'requestId': requestId,
      'result': ?result,
      'error': ?error,
    });
  }
}
