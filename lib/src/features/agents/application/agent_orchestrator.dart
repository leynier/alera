import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/features/session/domain/collab_agent.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_error_codes.dart';

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
    required List<Map<String, dynamic>> input,
    required String model,
    required String reasoningEffort,
    required String cwd,
    String approvalPolicy = 'never',
    Map<String, dynamic>? collaborationMode,
  }) async {
    final response = await _client.startTurn(
      threadId: threadId,
      input: input,
      model: model,
      reasoningEffort: reasoningEffort,
      cwd: cwd,
      approvalPolicy: approvalPolicy,
      collaborationMode: collaborationMode,
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

  /// Requests manual context compaction for the given thread.
  Future<void> compactThread({required String threadId}) {
    return _client.compactThread(threadId: threadId);
  }

  /// Steers an active turn with new input (redirect mid-turn).
  /// Returns the new turn ID.
  Future<String> steerTurn({
    required String threadId,
    required List<Map<String, dynamic>> input,
    required String expectedTurnId,
  }) async {
    final response = await _client.steerTurn(
      threadId: threadId,
      input: input,
      expectedTurnId: expectedTurnId,
    );
    final turnId =
        (response['result'] as Map<String, dynamic>?)?['turnId'] as String? ??
        (response['result'] as Map<String, dynamic>?)?['turn_id'] as String?;
    return turnId ?? expectedTurnId;
  }

  Future<void> close() async {
    await _notificationSub?.cancel();
    await _requestSub?.cancel();
    await _eventsController.close();
    await _client.close();
  }

  Future<void> approveRequest(Object requestId, {bool forSession = false}) {
    return _client.respondApproval(
      requestId: requestId,
      decision: 'accept',
      forSession: forSession,
    );
  }

  Future<void> declineRequest(Object requestId) {
    return _client.respondApproval(requestId: requestId, decision: 'reject');
  }

  String _describeApprovalRequest(String method, Map<String, dynamic> params) {
    if (method == 'item/commandExecution/requestApproval') {
      final cmd =
          params['command']?.toString() ??
          params['cmd']?.toString() ??
          params['args']?.toString();
      if (cmd != null && cmd.isNotEmpty) {
        return 'Run command: $cmd';
      }
      return 'Run a command';
    }
    if (method == 'item/fileChange/requestApproval') {
      final path = params['path']?.toString() ?? params['filePath']?.toString();
      if (path != null && path.isNotEmpty) {
        return 'Modify file: $path';
      }
      return 'Modify a file';
    }
    return 'Approve action';
  }

  String? _optionalId(Object? value) {
    final raw = value?.toString();
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _handleIncomingRequest(JsonRpcServerRequest request) {
    final method = request.method;

    if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      final params = request.params;
      final description = _describeApprovalRequest(method, params);
      final threadId = _optionalId(params['threadId']);
      _eventsController.add(
        AgentApprovalRequestEvent(
          requestId: request.id,
          method: method,
          description: description,
          threadId: threadId,
        ),
      );
      return;
    }

    if (method == 'item/tool/call') {
      final tool = (request.params['tool'] ?? '').toString();
      final arguments =
          (request.params['arguments'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      _eventsController.add(
        AgentToolCallRequestEvent(
          requestId: request.id,
          threadId: (request.params['threadId'] ?? '').toString(),
          turnId: (request.params['turnId'] ?? '').toString(),
          tool: tool,
          arguments: arguments,
        ),
      );
      // Handle sub-agent tool calls
      if (tool == toolNameRemoteAgent || tool == toolNameSubAgent) {
        // Sub-agent calls are handled by the timeline system
        // Respond with success to acknowledge receipt
        // The actual results will be streamed via timeline events
        unawaited(
          _client.respondToolCall(
            requestId: request.id,
            contentItems: const <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'text': 'Sub-agent execution started'},
            ],
            success: true,
          ),
        );
      } else {
        // Other tool calls not yet supported
        unawaited(
          _client.respondError(
            requestId: request.id,
            code: jsonRpcMethodNotFound,
            message: 'Tool calls are not supported in this build',
          ),
        );
      }
      return;
    }

    if (method == 'item/tool/requestUserInput' ||
        method == 'item/tool/request_user_input') {
      final params = request.params;
      final rawQuestions = params['questions'];
      final questions = (rawQuestions is List)
          ? rawQuestions.whereType<Map<String, dynamic>>().toList(
              growable: false,
            )
          : const <Map<String, dynamic>>[];
      _eventsController.add(
        AgentUserInputRequestEvent(
          requestId: request.id,
          threadId: _optionalId(params['threadId']),
          turnId: (params['turnId'] ?? '').toString(),
          itemId: (params['itemId'] ?? '').toString(),
          questions: questions,
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

  Future<void> respondUserInput(
    Object requestId,
    Map<String, dynamic> answers,
  ) {
    return _client.respondUserInput(requestId: requestId, answers: answers);
  }

  /// Requests manual context compaction for the given thread.
  Future<void> compactThread({required String threadId}) {
    return _client.compactThread(threadId: threadId);
  }
}
