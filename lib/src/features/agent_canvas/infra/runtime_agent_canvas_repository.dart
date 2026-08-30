import 'dart:async';

import 'package:alera/src/features/agent_canvas/domain/agent_canvas.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RuntimeAgentCanvasRepository(
  final RuntimeHostClient _client, {
  RuntimeChangeCoalescer? coalescer,
}) {
  this : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeChangeCoalescer _coalescer;

  Future<List<AgentCanvas>> list(
    String workspaceId, {
    bool includeHistory = true,
  }) async {
    final payload = await _client.runtimeRequest(
      'agentCanvas.catalog',
      <String, Object?>{
        'workspaceId': workspaceId,
        'includeHistory': includeHistory,
      },
    );
    final map = _map(payload);
    final canvases = map['canvases'];
    if (canvases is! List) {
      return const <AgentCanvas>[];
    }
    return <AgentCanvas>[
      for (final value in canvases)
        if (value is Map) AgentCanvas.fromJson(_map(value)),
    ];
  }

  Stream<List<AgentCanvas>> watch(String workspaceId) {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'agentCanvasChanged'},
      readSnapshot: () => list(workspaceId),
      coalesceKey: 'agentCanvas:$workspaceId',
      coalescer: _coalescer,
      matchesScope: runtimeScopeMatcher('workspaceId', workspaceId),
    );
  }

  Future<Map<String, Object?>> capabilities() async {
    final payload = await _client.runtimeRequest('agentCanvas.capabilities');
    return _map(payload);
  }

  Future<AgentCanvas> publish({
    required String workspaceId,
    required String terminalSessionId,
    required Map<String, Object?> document,
    String? tabId,
    String? agentType,
    String? title,
    String? canvasId,
    int? expectedRevision,
    AgentCanvasState? state,
  }) async {
    final payload = await _client.runtimeRequest(
      'agentCanvas.publish',
      <String, Object?>{
        'workspaceId': workspaceId,
        'terminalSessionId': terminalSessionId,
        'tabId': ?tabId,
        'agentType': ?agentType,
        'title': ?title,
        'canvasId': ?canvasId,
        'expectedRevision': ?expectedRevision,
        'state': ?state?.name,
        'document': document,
      },
    );
    return AgentCanvas.fromJson(_map(_map(payload)['canvas']));
  }

  Future<AgentCanvasDecision> resolveDecision({
    required String decisionId,
    required Object? resolution,
  }) async {
    final payload = await _client.runtimeRequest(
      'agentCanvas.decision.resolve',
      <String, Object?>{'decisionId': decisionId, 'resolution': resolution},
    );
    return AgentCanvasDecision.fromJson(_map(_map(payload)['decision']));
  }

  Future<bool> waitForDecision({
    required String decisionId,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) < timeout) {
      final payload = await _client.runtimeRequest(
        'agentCanvas.wait',
        <String, Object?>{'decisionId': decisionId},
      );
      if (_map(payload)['ready'] == true) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<AgentCanvas> complete(String canvasId) =>
      _changeState('agentCanvas.complete', canvasId);

  Future<AgentCanvas> close(String canvasId) =>
      _changeState('agentCanvas.close', canvasId);

  Future<AgentCanvas> pin(String canvasId, bool pinned) async {
    final payload = await _client.runtimeRequest(
      'agentCanvas.pin',
      <String, Object?>{'canvasId': canvasId, 'pinned': pinned},
    );
    return AgentCanvas.fromJson(_map(_map(payload)['canvas']));
  }

  Future<void> remove(String canvasId) async {
    await _client.runtimeRequest('agentCanvas.remove', <String, Object?>{
      'canvasId': canvasId,
    });
  }

  Future<Object?> action({
    required String canvasId,
    required Map<String, Object?> action,
  }) {
    return _client.runtimeRequest('agentCanvas.action', <String, Object?>{
      'canvasId': canvasId,
      'action': action,
    });
  }

  Future<AgentCanvas> _changeState(String requestType, String canvasId) async {
    final payload = await _client.runtimeRequest(requestType, <String, Object?>{
      'canvasId': canvasId,
    });
    return AgentCanvas.fromJson(_map(_map(payload)['canvas']));
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException(
    'Agent Canvas runtime payload must be an object.',
  );
}
