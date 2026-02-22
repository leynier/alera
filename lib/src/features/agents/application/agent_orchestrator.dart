import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';

class AgentOrchestrator {
  AgentOrchestrator(this._client);

  final CodexAppServerClient _client;
  final StreamController<AgentOrchestratorEvent> _eventsController =
      StreamController<AgentOrchestratorEvent>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<JsonRpcServerRequest>? _requestSub;

  Stream<AgentOrchestratorEvent> get events => _eventsController.stream;

  Future<void> boot() async {
    await _client.start();

    _notificationSub = _client.events.listen((payload) {
      final method = payload['method'];
      if (method is! String) {
        return;
      }
      _eventsController.add(
        AgentNotificationEvent(method: method, payload: payload),
      );
    });

    _requestSub = _client.requests.listen(_handleIncomingRequest);
  }

  Future<String> ensureThread({String? existingThreadId, String? cwd}) async {
    if (existingThreadId != null) {
      try {
        final resumed = await _client.resumeThread(existingThreadId);
        final thread = (resumed['result'] as Map<String, dynamic>?)?['thread'];
        final id = (thread as Map<String, dynamic>?)?['id'] as String?;
        if (id == null || id.isEmpty) {
          throw StateError('app-server resume returned no thread id');
        }
        return id;
      } catch (error) {
        if (!_isRecoverableResumeError(error)) {
          rethrow;
        }
      }
    }

    final result = await _client.startThread(cwd: cwd, approvalPolicy: 'never');
    final thread = (result['result'] as Map<String, dynamic>?)?['thread'];
    final id = (thread as Map<String, dynamic>?)?['id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('app-server start returned no thread id');
    }

    return id;
  }

  bool _isRecoverableResumeError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('no rollout found for thread id') ||
        lower.contains('thread not found')) {
      return true;
    }

    const prefix = 'Bad state:';
    final payload = raw.startsWith(prefix)
        ? raw.substring(prefix.length).trim()
        : raw;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      final message = decoded['message']?.toString().toLowerCase() ?? '';
      return message.contains('no rollout found for thread id') ||
          message.contains('thread not found');
    } catch (_) {
      return false;
    }
  }

  Future<String> runTurn({
    required String threadId,
    required String prompt,
    required String model,
    required String reasoningEffort,
    required String cwd,
  }) async {
    final response = await _client.startTurn(
      threadId: threadId,
      input: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': prompt},
      ],
      model: model,
      reasoningEffort: reasoningEffort,
      cwd: cwd,
      approvalPolicy: 'never',
    );

    final turn = (response['result'] as Map<String, dynamic>?)?['turn'];
    final turnId = (turn as Map<String, dynamic>?)?['id'] as String?;
    if (turnId == null || turnId.isEmpty) {
      throw StateError('app-server did not return a turn id');
    }
    return turnId;
  }

  Future<void> interrupt({required String threadId, required String turnId}) {
    return _client.interruptTurn(threadId: threadId, turnId: turnId);
  }

  Future<void> close() async {
    await _notificationSub?.cancel();
    await _requestSub?.cancel();
    await _eventsController.close();
    await _client.close();
  }

  void _handleIncomingRequest(JsonRpcServerRequest request) {
    final method = request.method;

    if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      unawaited(
        _client.respondApproval(
          requestId: request.id,
          decision: 'accept',
          forSession: true,
        ),
      );
      return;
    }

    if (method == 'item/tool/call') {
      _eventsController.add(
        AgentToolCallRequestEvent(
          requestId: request.id,
          threadId: (request.params['threadId'] ?? '').toString(),
          turnId: (request.params['turnId'] ?? '').toString(),
          tool: (request.params['tool'] ?? '').toString(),
          arguments:
              (request.params['arguments'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        ),
      );
      unawaited(
        _client.respondError(
          requestId: request.id,
          code: -32601,
          message: 'tool calls are not supported in this build',
        ),
      );
      return;
    }

    _eventsController.add(
      AgentNotificationEvent(
        method: method,
        payload: <String, dynamic>{
          'method': method,
          'params': request.params,
          'id': request.id,
        },
      ),
    );
  }
}
