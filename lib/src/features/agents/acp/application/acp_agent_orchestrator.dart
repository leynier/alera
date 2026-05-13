import 'dart:async';

import 'package:alera/src/features/agents/acp/infrastructure/codex_acp_client.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:uuid/uuid.dart';

/// ACP-flavored counterpart of `AgentOrchestrator`. Mirrors its public surface
/// (boot/ensureThread/runTurn/interrupt/approve/decline/close + events stream)
/// and emits the same `AgentOrchestratorEvent` types so a future unification
/// can swap implementations without touching consumers.
///
/// "Thread" terminology is preserved on the API for parity with the Codex
/// path; internally a thread maps 1:1 to an ACP `sessionId`.
class AcpAgentOrchestrator {
  AcpAgentOrchestrator(this._client);

  final CodexAcpClient _client;
  final Uuid _uuid = const Uuid();

  final StreamController<AgentOrchestratorEvent> _eventsController =
      StreamController<AgentOrchestratorEvent>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<JsonRpcServerRequest>? _requestSub;

  Stream<AgentOrchestratorEvent> get events => _eventsController.stream;

  Future<void> boot() async {
    await _client.start();

    _notificationSub = _client.events.listen(_handleNotification);
    _requestSub = _client.requests.listen(_handleIncomingRequest);
  }

  /// ACP gives no native session resume in the current `codex-acp` build, so
  /// `existingThreadId` is honored only as a best-effort `session/load` and
  /// silently falls back to `session/new` when the agent rejects it.
  Future<String> ensureThread({String? existingThreadId, String? cwd}) async {
    final workspace = cwd ?? '.';
    if (existingThreadId != null && existingThreadId.isNotEmpty) {
      try {
        return await _client.loadSession(
          sessionId: existingThreadId,
          cwd: workspace,
        );
      } catch (_) {
        // Fall through to new session.
      }
    }
    return _client.newSession(cwd: workspace);
  }

  /// Sends a user prompt as a `session/prompt` request, returning a synthetic
  /// turn id immediately. Streaming agent output arrives on [events] as
  /// `AgentNotificationEvent`s with `method == 'session/update'`. A final
  /// `turn/completed` (or `turn/failed`) notification is emitted when the
  /// underlying request settles.
  Future<String> runTurn({
    required String threadId,
    required List<Map<String, dynamic>> input,
    String? cwd,
  }) async {
    final turnId = _uuid.v4();

    unawaited(
      _client
          .prompt(sessionId: threadId, content: input)
          .then(
            (stopReason) {
              _eventsController.add(
                AgentNotificationEvent(
                  method: 'turn/completed',
                  payload: <String, dynamic>{
                    'method': 'turn/completed',
                    'params': <String, dynamic>{
                      'sessionId': threadId,
                      'turnId': turnId,
                      'stopReason': stopReason,
                    },
                  },
                ),
              );
            },
            onError: (Object error) {
              _eventsController.add(
                AgentNotificationEvent(
                  method: 'turn/failed',
                  payload: <String, dynamic>{
                    'method': 'turn/failed',
                    'params': <String, dynamic>{
                      'sessionId': threadId,
                      'turnId': turnId,
                      'error': error.toString(),
                    },
                  },
                ),
              );
            },
          ),
    );

    return turnId;
  }

  Future<void> interrupt({required String threadId, String? turnId}) {
    return _client.cancel(sessionId: threadId);
  }

  Future<void> approveRequest(Object requestId, {String optionId = 'allow'}) {
    return _client.respondPermission(
      requestId: requestId,
      optionId: optionId,
    );
  }

  Future<void> declineRequest(Object requestId) {
    return _client.declinePermission(requestId: requestId);
  }

  Future<void> close() async {
    await _notificationSub?.cancel();
    await _requestSub?.cancel();
    await _eventsController.close();
    await _client.close();
  }

  // ACP gaps — preserved for surface parity with AgentOrchestrator. Calls land
  // here as loud failures rather than silent no-ops.
  Future<Never> startReview() {
    throw UnsupportedError(
      'review/start has no ACP equivalent. Use a "/review" prompt instead.',
    );
  }

  Future<Never> compactThread() {
    throw UnsupportedError(
      'thread/compact/start has no ACP equivalent. Use a "/compact" prompt instead.',
    );
  }

  Future<Never> setThreadName() {
    throw UnsupportedError('thread/name/set is not part of ACP.');
  }

  Future<Never> steerTurn() {
    throw UnsupportedError(
      'turn/steer has no ACP equivalent. Cancel and send a new prompt.',
    );
  }

  void _handleNotification(Map<String, dynamic> payload) {
    final method = payload['method'];
    if (method is! String) {
      return;
    }
    _eventsController.add(
      AgentNotificationEvent(method: method, payload: payload),
    );
  }

  void _handleIncomingRequest(JsonRpcServerRequest request) {
    if (request.method == 'session/request_permission') {
      _eventsController.add(
        AgentApprovalRequestEvent(
          requestId: request.id,
          method: request.method,
          description: _describePermission(request.params),
          threadId: _optionalString(request.params['sessionId']),
        ),
      );
      return;
    }

    // fs/* and terminal/* are handled inside CodexAcpClient.
    if (request.method.startsWith('fs/') ||
        request.method.startsWith('terminal/')) {
      return;
    }

    // Anything else surfaces as a generic notification so the UI can log it.
    _eventsController.add(
      AgentNotificationEvent(
        method: request.method,
        payload: <String, dynamic>{
          'method': request.method,
          'params': request.params,
          'id': request.id,
        },
      ),
    );
  }

  String _describePermission(Map<String, dynamic> params) {
    final toolCall = params['toolCall'];
    if (toolCall is Map) {
      final cast = toolCall.cast<String, dynamic>();
      final title = cast['title'] ?? cast['kind'] ?? cast['name'];
      if (title is String && title.isNotEmpty) {
        return title;
      }
    }
    final options = params['options'];
    if (options is List && options.isNotEmpty) {
      return 'Approve action (${options.length} options)';
    }
    return 'Approve action';
  }

  String? _optionalString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
