import 'dart:async';

import 'package:alera/src/features/agents/acp/infrastructure/codex_acp_client.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_error_codes.dart';
import 'package:uuid/uuid.dart';

/// ACP-flavored counterpart of `AgentOrchestrator`. Mirrors its public surface
/// (boot/ensureThread/runTurn/interrupt/approve/decline/close + events stream)
/// and emits the same `AgentOrchestratorEvent` types so a future unification
/// can swap implementations without touching consumers.
///
/// ## Thread / session terminology
///
/// "Thread" is preserved on the API for parity with the Codex path; an ACP
/// `sessionId` maps 1:1 onto it.
///
/// ## Turn lifecycle parity
///
/// [runTurn] awaits the underlying `session/prompt` request and emits three
/// synthetic Codex-shape notifications so downstream consumers
/// (`SessionService`, `SessionTimelineReducer`) can process ACP and Codex
/// turns uniformly:
///
/// ```
/// {params: {turn: {id, threadId, status: 'started'|'completed'|'failed',
///                  stopReason?, error?}}}
/// ```
///
/// A failed prompt rejects the returned Future AND emits `turn/failed`, so
/// callers see errors synchronously instead of having to subscribe to the
/// events stream just to know whether a prompt was accepted.
///
/// ## ACP gaps
///
/// `startReview`, `compactThread`, `setThreadName`, and `steerTurn` are
/// preserved on the surface but throw `UnsupportedError` because ACP has no
/// equivalent. They are marked `async` so the throw produces a rejected
/// Future for `.catchError` consumers.
///
/// `interrupt` accepts a `threadId` only; ACP `session/cancel` is
/// session-scoped fire-and-forget, so per-turn cancellation is not
/// representable.
class AcpAgentOrchestrator {
  AcpAgentOrchestrator(this._client);

  final CodexAcpClient _client;
  final Uuid _uuid = const Uuid();

  final StreamController<AgentOrchestratorEvent> _eventsController =
      StreamController<AgentOrchestratorEvent>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  StreamSubscription<JsonRpcServerRequest>? _requestSub;
  var _booted = false;
  var _closed = false;

  Stream<AgentOrchestratorEvent> get events => _eventsController.stream;

  /// Spawns the agent, subscribes to its event streams BEFORE the
  /// `initialize` handshake, then performs the handshake. The pre-handshake
  /// subscription guarantees notifications emitted during initialize
  /// (e.g. stderr banners, early `session/update` events) are not dropped
  /// by Dart's broadcast-stream-no-buffer semantics.
  Future<void> boot() async {
    if (_booted || _closed) {
      return;
    }
    await _client.start();

    _notificationSub = _client.events.listen(
      _handleNotification,
      onError: _forwardError,
    );
    _requestSub = _client.requests.listen(
      _handleIncomingRequest,
      onError: _forwardError,
    );

    await _client.initialize();
    _booted = true;
  }

  /// ACP gives no native session resume in the current `codex-acp` build, so
  /// `existingThreadId` is honored only as a best-effort `session/load` and
  /// falls back to `session/new` when the agent rejects it.
  ///
  /// Only `StateError` is treated as recoverable (that is the exception type
  /// `JsonRpcClient` raises for protocol-level rejections and closed
  /// transports). Anything else — e.g. `TypeError` from a malformed agent
  /// response, programming bugs — propagates to the caller.
  Future<String> ensureThread({String? existingThreadId, String? cwd}) async {
    final workspace = cwd ?? '.';
    if (existingThreadId != null && existingThreadId.isNotEmpty) {
      try {
        return await _client.loadSession(
          sessionId: existingThreadId,
          cwd: workspace,
        );
      } on StateError {
        // Fall through to new session.
      }
    }
    return _client.newSession(cwd: workspace);
  }

  /// Sends a user prompt as a `session/prompt` request. Resolves with the
  /// synthetic turn id when the agent's response settles. Streaming agent
  /// output arrives on [events] as `AgentNotificationEvent`s with
  /// `method == 'session/update'`.
  ///
  /// Three lifecycle notifications are emitted in Codex shape
  /// (`{params: {turn: {id, threadId, status, stopReason?, error?}}}`):
  /// `turn/started` immediately before the request is sent,
  /// `turn/completed` on a successful agent response, and `turn/failed` on
  /// error. Failures also reject the returned Future so synchronous callers
  /// see them.
  Future<String> runTurn({
    required String threadId,
    required List<Map<String, dynamic>> input,
  }) async {
    final turnId = _uuid.v4();
    _emitTurnLifecycle(
      method: 'turn/started',
      threadId: threadId,
      turnId: turnId,
      status: 'started',
    );

    try {
      final stopReason = await _client.prompt(
        sessionId: threadId,
        content: input,
      );
      _emitTurnLifecycle(
        method: 'turn/completed',
        threadId: threadId,
        turnId: turnId,
        status: 'completed',
        stopReason: stopReason,
      );
      return turnId;
    } catch (error) {
      _emitTurnLifecycle(
        method: 'turn/failed',
        threadId: threadId,
        turnId: turnId,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
  }

  void _emitTurnLifecycle({
    required String method,
    required String threadId,
    required String turnId,
    required String status,
    String? stopReason,
    String? error,
  }) {
    final turn = <String, dynamic>{
      'id': turnId,
      'threadId': threadId,
      'status': status,
      'stopReason': ?stopReason,
      'error': ?error,
    };
    _emit(
      AgentNotificationEvent(
        method: method,
        payload: <String, dynamic>{
          'method': method,
          'params': <String, dynamic>{'turn': turn},
        },
      ),
    );
  }

  /// ACP `session/cancel` is session-scoped and fire-and-forget — there is no
  /// per-turn cancellation, so [interrupt] takes no `turnId`.
  Future<void> interrupt({required String threadId}) {
    return _client.cancel(sessionId: threadId);
  }

  Future<void> approveRequest(Object requestId, {String optionId = 'allow'}) {
    return _client.respondPermission(requestId: requestId, optionId: optionId);
  }

  Future<void> declineRequest(Object requestId) {
    return _client.declinePermission(requestId: requestId);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    await _notificationSub?.cancel();
    await _requestSub?.cancel();
    try {
      await _client.close();
    } finally {
      await _eventsController.close();
    }
  }

  // ACP gaps — preserved for surface parity with AgentOrchestrator. Marked
  // `async` so the throws produce rejected Futures (instead of synchronous
  // throws that bypass Future-style `.catchError`).
  Future<Never> startReview() async {
    throw UnsupportedError(
      'review/start has no ACP equivalent. Use a "/review" prompt instead.',
    );
  }

  Future<Never> compactThread() async {
    throw UnsupportedError(
      'thread/compact/start has no ACP equivalent. Use a "/compact" prompt instead.',
    );
  }

  Future<Never> setThreadName() async {
    throw UnsupportedError('thread/name/set is not part of ACP.');
  }

  Future<Never> steerTurn() async {
    throw UnsupportedError(
      'turn/steer has no ACP equivalent. Cancel and send a new prompt.',
    );
  }

  void _handleNotification(Map<String, dynamic> payload) {
    final method = payload['method'];
    if (method is! String) {
      return;
    }
    _emit(AgentNotificationEvent(method: method, payload: payload));
  }

  void _handleIncomingRequest(JsonRpcServerRequest request) {
    if (request.method == 'session/request_permission') {
      final options = _permissionOptions(request.params['options']);
      _emit(
        AgentApprovalRequestEvent(
          requestId: request.id,
          method: request.method,
          description: _describePermission(request.params, options),
          threadId: _optionalString(request.params['sessionId']),
          options: options,
        ),
      );
      return;
    }

    // fs/* and terminal/* are handled inside CodexAcpClient.
    if (request.method.startsWith('fs/') ||
        request.method.startsWith('terminal/')) {
      return;
    }

    // Anything else: surface as a notification so the UI can log it, AND
    // respond with methodNotFound so the agent doesn't deadlock on the
    // pending request id.
    _emit(
      AgentNotificationEvent(
        method: request.method,
        payload: <String, dynamic>{
          'method': request.method,
          'params': request.params,
          'id': request.id,
        },
      ),
    );
    unawaited(
      _client.respondError(
        requestId: request.id,
        code: jsonRpcMethodNotFound,
        message: 'Method not supported by client: ${request.method}',
      ),
    );
  }

  void _emit(AgentOrchestratorEvent event) {
    if (_closed || _eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  void _forwardError(Object error, StackTrace stackTrace) {
    if (_closed || _eventsController.isClosed) {
      return;
    }
    _eventsController.addError(error, stackTrace);
  }

  String _describePermission(
    Map<String, dynamic> params,
    List<AgentApprovalOption> options,
  ) {
    final toolCall = params['toolCall'];
    if (toolCall is Map) {
      final cast = toolCall.cast<String, dynamic>();
      final label =
          _optionalDisplayString(cast['title']) ??
          _optionalDisplayString(cast['kind']) ??
          _optionalDisplayString(cast['name']);
      if (label != null) {
        return label;
      }
    }
    if (options.isNotEmpty) {
      return 'Approve action (${options.length} options)';
    }
    return 'Approve action';
  }

  List<AgentApprovalOption> _permissionOptions(Object? options) {
    if (options is! List) {
      return const <AgentApprovalOption>[];
    }
    return <AgentApprovalOption>[
      for (final option in options)
        if (option is Map)
          if (_optionalString(option['optionId']) case final optionId?)
            AgentApprovalOption(
              optionId: optionId,
              name:
                  _optionalDisplayString(option['name']) ??
                  _sentenceCaseOptionId(optionId),
              kind: _optionalDisplayString(option['kind']),
            ),
    ];
  }

  String _sentenceCaseOptionId(String optionId) {
    final words = optionId.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) {
      return optionId;
    }
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Coerces an opaque protocol identifier (sessionId, optionId, threadId, ...)
  /// to a non-empty `String`. Does NOT trim — these values must be returned to
  /// the agent byte-for-byte.
  String? _optionalString(Object? value) {
    if (value is! String) {
      return null;
    }
    return value.isEmpty ? null : value;
  }

  /// Coerces a human-readable string (name, kind, title, ...) to a non-empty
  /// trimmed `String`. Surrounding whitespace is stripped.
  String? _optionalDisplayString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
