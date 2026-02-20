import 'dart:async';

import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/models/contracts.dart';

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
      final resumed = await _client.resumeThread(existingThreadId);
      final thread = (resumed['result'] as Map<String, dynamic>?)?['thread'];
      final id = (thread as Map<String, dynamic>?)?['id'] as String?;
      if (id == null || id.isEmpty) {
        throw StateError('app-server resume returned no thread id');
      }
      return id;
    }

    final result = await _client.startThread(cwd: cwd);
    final thread = (result['result'] as Map<String, dynamic>?)?['thread'];
    final id = (thread as Map<String, dynamic>?)?['id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('app-server start returned no thread id');
    }

    return id;
  }

  Future<String> runTurn({
    required String threadId,
    required String prompt,
    required String plannerModel,
    required String executorModel,
    required ExecutionMode mode,
    required bool fullAccess,
    required String cwd,
  }) async {
    final model = mode == ExecutionMode.plan ? plannerModel : executorModel;
    final approvalPolicy = _approvalPolicy(mode: mode, fullAccess: fullAccess);
    final collaborationMode = mode == ExecutionMode.plan ? 'plan' : null;

    final response = await _client.startTurn(
      threadId: threadId,
      input: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': prompt},
      ],
      model: model,
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

  Future<String> startReview({
    required String threadId,
    String delivery = 'inline',
  }) async {
    final response = await _client.reviewStart(threadId, delivery: delivery);
    final result = response['result'] as Map<String, dynamic>?;
    final turn = result?['turn'] as Map<String, dynamic>?;
    final turnId = turn?['id'] as String?;
    if (turnId == null || turnId.isEmpty) {
      throw StateError('review/start did not return a turn id');
    }
    return turnId;
  }

  Future<void> interrupt({
    required String threadId,
    required String turnId,
  }) {
    return _client.interruptTurn(threadId: threadId, turnId: turnId);
  }

  Future<void> resolveApproval({
    required PendingApproval approval,
    required ApprovalDecisionType decision,
    AllowScope? allowScope,
  }) {
    return _client.respondApproval(
      requestId: approval.requestId,
      decision: decision,
      allowScope: allowScope,
    );
  }

  Future<void> close() async {
    await _notificationSub?.cancel();
    await _requestSub?.cancel();
    await _eventsController.close();
    await _client.close();
  }

  void _handleIncomingRequest(JsonRpcServerRequest request) {
    final method = request.method;

    if (method == 'item/commandExecution/requestApproval') {
      _eventsController.add(
        AgentApprovalRequestEvent(
          approval: PendingApproval(
            requestId: request.id,
            itemType: ApprovalItemType.commandExecution,
            threadId: (request.params['threadId'] ?? '').toString(),
            turnId: (request.params['turnId'] ?? '').toString(),
            itemId: (request.params['itemId'] ?? '').toString(),
            approvalId: request.params['approvalId']?.toString(),
            reason: request.params['reason']?.toString(),
            command: request.params['command']?.toString(),
            cwd: request.params['cwd']?.toString(),
            commandActions: (request.params['commandActions'] as List?)
                    ?.map((item) => item.toString())
                    .toList(growable: false) ??
                const <String>[],
          ),
        ),
      );
      return;
    }

    if (method == 'item/fileChange/requestApproval') {
      _eventsController.add(
        AgentApprovalRequestEvent(
          approval: PendingApproval(
            requestId: request.id,
            itemType: ApprovalItemType.fileChange,
            threadId: (request.params['threadId'] ?? '').toString(),
            turnId: (request.params['turnId'] ?? '').toString(),
            itemId: (request.params['itemId'] ?? '').toString(),
            reason: request.params['reason']?.toString(),
          ),
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
          arguments: (request.params['arguments'] as Map?)
                  ?.cast<String, dynamic>() ??
              const <String, dynamic>{},
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

  String _approvalPolicy({
    required ExecutionMode mode,
    required bool fullAccess,
  }) {
    if (mode == ExecutionMode.plan) {
      return 'on-request';
    }
    if (fullAccess) {
      return 'never';
    }
    return 'on-request';
  }
}
