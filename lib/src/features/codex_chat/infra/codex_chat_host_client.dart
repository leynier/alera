import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

// Covers app-server initialization, the 90-second scan, native fork/boundary
// requests, and response overhead. Keep ordinary runtime requests short.
const _codexHistoryOperationTimeout = Duration(minutes: 7);

class CodexChatHostClient {
  CodexChatHostClient(this._client) {
    _runtimeEvents = _client.runtimeEvents.listen(_handleRuntimeEvent);
  }

  final RuntimeHostClient _client;
  late final StreamSubscription<RuntimeHostEvent> _runtimeEvents;
  Future<Set<String>>? _runtimeCapabilities;

  Stream<RuntimeHostEvent> get events => _client.runtimeEvents;

  void _handleRuntimeEvent(RuntimeHostEvent event) {
    if (event.name == aleraRuntimeHostConnectedEvent) {
      _runtimeCapabilities = null;
    }
  }

  void dispose() {
    unawaited(_runtimeEvents.cancel());
  }

  Future<Set<String>> refreshChatFeatures() async {
    // A failed status request must not look like a runtime downgrade.
    final status = await request('status.get');
    final capabilities = asTerminalHostStringList(
      status['runtimeCapabilities'],
    ).toSet();
    _runtimeCapabilities = Future.value(capabilities);
    return capabilities.intersection(const {
      'codexForkV1',
      'codexHistoryEditV1',
      'codexSharedQueueV1',
    });
  }

  Future<bool> supportsSharedQueue() async =>
      (await _capabilities()).contains('codexSharedQueueV1');

  Future<bool> supportsSessions() async {
    final capabilities = await _capabilities();
    return capabilities.contains(aleraRuntimeHostCodexSessionsCapability);
  }

  Future<bool> supportsTurnPolicy() async {
    final capabilities = await _capabilities(retryAfterFailure: true);
    return capabilities.contains(aleraRuntimeHostCodexTurnPolicyCapability);
  }

  Future<bool> supportsGoals() async {
    final capabilities = await _capabilities(retryAfterFailure: true);
    return capabilities.contains(aleraRuntimeHostCodexGoalsCapability);
  }

  Future<Set<String>> _capabilities({bool retryAfterFailure = false}) async {
    final capabilities = await _capabilityRequest();
    if (!retryAfterFailure || _runtimeCapabilities != null) {
      return capabilities;
    }
    return _capabilityRequest();
  }

  Future<Set<String>> _capabilityRequest() {
    final cached = _runtimeCapabilities;
    if (cached != null) return cached;
    final requestFuture = () async {
      try {
        final status = await request('status.get');
        return asTerminalHostStringList(status['runtimeCapabilities']).toSet();
      } on Object {
        _runtimeCapabilities = null;
        return const <String>{};
      }
    }();
    _runtimeCapabilities = requestFuture;
    return requestFuture;
  }

  Future<Map<String, Object?>> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final timeout = switch (type) {
      'codex.thread.fork' ||
      'codex.thread.edit' ||
      'codex.queue.reconcile' => _codexHistoryOperationTimeout,
      _ => null,
    };
    final value = await _client.runtimeRequest(type, payload, timeout);
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw const FormatException('Codex host response must be an object.');
  }

  Future<Map<String, Object?>> openThread(String tabId) {
    return request('codex.thread.open', <String, Object?>{
      'tabId': tabId,
      'supportsMissingRolloutRecovery': true,
    });
  }

  Future<Map<String, Object?>> listThreads({
    String? workspaceId,
    String? searchTerm,
    String? cursor,
    int limit = 20,
  }) => request('codex.thread.list', <String, Object?>{
    'scope': workspaceId == null ? 'all' : 'workspace',
    'workspaceId': ?workspaceId,
    'searchTerm': ?searchTerm,
    'cursor': ?cursor,
    'limit': limit,
  });

  Future<Map<String, Object?>> resumeThread(
    String tabId,
    String threadId, {
    String? cwd,
    int limit = 20,
  }) => request('codex.thread.resume', <String, Object?>{
    'tabId': tabId,
    'threadId': threadId,
    'cwd': ?cwd,
    'limit': limit,
  });

  Future<Map<String, Object?>> history(
    String tabId, {
    String? cursor,
    int limit = 20,
  }) => request('codex.thread.history', <String, Object?>{
    'tabId': tabId,
    'cursor': ?cursor,
    'limit': limit,
  });

  Future<Map<String, Object?>> newThread(String tabId, {String? cwd}) =>
      request('codex.thread.new', <String, Object?>{
        'tabId': tabId,
        'cwd': ?cwd,
      });

  Future<Map<String, Object?>> clearThread(String tabId, {String? cwd}) =>
      request('codex.thread.clear', <String, Object?>{
        'tabId': tabId,
        'cwd': ?cwd,
      });

  Future<Map<String, Object?>> snapshot(String tabId) {
    return request('codex.thread.snapshot', <String, Object?>{'tabId': tabId});
  }

  Future<Map<String, Object?>> getGoal(String tabId) =>
      request('codex.goal.get', <String, Object?>{'tabId': tabId});

  Future<Map<String, Object?>> setGoal(
    String tabId, {
    required String? expectedThreadId,
    String? objective,
    String? status,
    int? tokenBudget,
    bool recordUserMessage = false,
    String? clientUserMessageId,
    Map<String, Object?>? configuration,
  }) => request('codex.goal.set', <String, Object?>{
    'tabId': tabId,
    'expectedThreadId': expectedThreadId,
    'objective': ?objective,
    'status': ?status,
    'tokenBudget': ?tokenBudget,
    'recordUserMessage': recordUserMessage,
    'clientUserMessageId': ?clientUserMessageId,
    'configuration': ?configuration,
  });

  Future<Map<String, Object?>> clearGoal(
    String tabId, {
    required String? expectedThreadId,
  }) => request('codex.goal.clear', <String, Object?>{
    'tabId': tabId,
    'expectedThreadId': expectedThreadId,
  });

  Future<Map<String, Object?>> configureTab(
    String tabId,
    Map<String, Object?> configuration,
  ) => request('codex.tab.configure', <String, Object?>{
    'tabId': tabId,
    'configuration': configuration,
  });

  Future<Map<String, Object?>> recoverThread(
    String tabId, {
    required String expectedThreadId,
  }) => request('codex.thread.recover', <String, Object?>{
    'tabId': tabId,
    'expectedThreadId': expectedThreadId,
  });

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
    required String? expectedThreadId,
    required Map<String, Object?> userMessage,
    String? model,
    required String reasoningEffort,
    required String speedMode,
    required String permissionMode,
    required bool planMode,
    String? collaborationMode,
    String? clientUserMessageId,
    bool sharedQueue = false,
    int? expectedHistoryRevision,
    Map<String, Object?>? draft,
  }) async {
    final effectiveCollaborationMode =
        collaborationMode ?? (planMode ? 'plan' : 'default');
    final supportsTurnPolicy = (await _capabilities(
      retryAfterFailure: true,
    )).contains(aleraRuntimeHostCodexTurnPolicyCapability);
    final wirePermissionMode =
        !supportsTurnPolicy && permissionMode == 'auto-review'
        ? 'on-request'
        : permissionMode;
    return request(
      sharedQueue ? 'codex.queue.add' : 'codex.turn.start',
      <String, Object?>{
        'draft': ?draft,
        'expectedHistoryRevision': ?expectedHistoryRevision,
        'tabId': tabId,
        'expectedThreadId': expectedThreadId,
        'input': input,
        'userMessage': userMessage,
        if (model != null && model.isNotEmpty) 'model': model,
        'reasoning': <String, Object?>{'effort': reasoningEffort},
        'effort': reasoningEffort,
        'clientUserMessageId': ?clientUserMessageId,
        'serviceTier': speedMode == 'fast' ? 'fast' : null,
        'approvalPolicy': supportsTurnPolicy
            ? switch (permissionMode) {
                'never' => 'never',
                'untrusted' => 'untrusted',
                _ => 'on-request',
              }
            : wirePermissionMode,
        if (supportsTurnPolicy)
          'approvalsReviewer': permissionMode == 'auto-review'
              ? 'auto_review'
              : 'user',
        if (supportsTurnPolicy)
          'sandboxPolicy': permissionMode == 'never'
              ? <String, Object?>{'type': 'dangerFullAccess'}
              : <String, Object?>{
                  'type': 'workspaceWrite',
                  'writableRoots': const <String>[],
                  'networkAccess': false,
                },
        'collaborationMode': <String, Object?>{
          'mode': effectiveCollaborationMode,
          'settings': <String, Object?>{
            if (model != null && model.isNotEmpty) 'model': model,
            'reasoning_effort': reasoningEffort,
          },
        },
        'configuration': <String, Object?>{
          'selectedModel': model,
          'reasoningEffort': reasoningEffort,
          'speedMode': speedMode,
          'permissionMode': wirePermissionMode,
          'planMode': planMode,
          'collaborationMode': effectiveCollaborationMode,
        },
      },
    );
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
    List<Map<String, Object?>> input, {
    required Map<String, Object?> userMessage,
    String? clientUserMessageId,
    String? expectedThreadId,
    int? expectedHistoryRevision,
    bool sharedQueue = false,
    Map<String, Object?>? draft,
  }) {
    return request(
      sharedQueue ? 'codex.queue.add' : 'codex.turn.steer',
      <String, Object?>{
        'expectedThreadId': expectedThreadId,
        'draft': ?draft,
        'expectedHistoryRevision': ?expectedHistoryRevision,
        'tabId': tabId,
        'turnId': turnId,
        'input': input,
        'userMessage': userMessage,
        'clientUserMessageId': ?clientUserMessageId,
      },
    );
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
    String? commitTitle,
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
    if (target == 'commit' && commitTitle?.trim().isNotEmpty == true) {
      targetPayload['title'] = commitTitle!.trim();
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

  Future<void> snoozeRequest(Object requestId) async {
    await request('codex.request.snooze', <String, Object?>{
      'requestId': requestId,
    });
  }
}
