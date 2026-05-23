import 'dart:async';
import 'dart:io';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_error_codes.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

/// Thin client over the Agent Client Protocol (ACP) — speaks newline-delimited
/// JSON-RPC 2.0 over the spawned agent's stdio. Built on top of the shared
/// [JsonRpcClient] so all framing, request/response correlation, and stderr
/// forwarding behave the same as the existing Codex app-server transport.
///
/// ## Lifecycle (two-phase)
///
/// Construction does not spawn anything. Callers must explicitly call
/// [start] (spawns the process, attaches the internal `fs/*` handler) and
/// then [initialize] (performs the `initialize` handshake). Splitting these
/// lets the [AcpAgentOrchestrator] attach its event subscribers between the
/// two so notifications emitted during the handshake are not dropped by
/// Dart broadcast-stream-no-buffer semantics. Both methods are idempotent.
///
/// ## Filesystem sandbox
///
/// `fs/read_text_file` and `fs/write_text_file` requests from the agent are
/// served against [dart:io] but constrained to the session's working
/// directory for the request's `sessionId` (set by [newSession]/[loadSession]).
/// Absolute paths outside the session cwd, relative paths, unknown sessions,
/// and requests with no `sessionId` are rejected with `invalidParams`.
/// Symlink-based escapes are not blocked (closed-beta acceptable limitation).
///
/// ## Protocol version
///
/// [initialize] emits a synthetic `alera.protocolVersionMismatch`
/// notification when the agent's returned `protocolVersion` differs from
/// the requested one, so the UI can surface a warning instead of silently
/// proceeding with an incompatible contract.
class CodexAcpClient {
  CodexAcpClient({
    required ProcessRunner processRunner,
    String executable = 'codex-acp',
    List<String> arguments = const <String>[],
    String? workingDirectory,
    Map<String, String>? environment,
    int protocolVersion = 1,
  }) : _rpc = JsonRpcClient(
         processRunner: processRunner,
         executable: executable,
         arguments: arguments,
         workingDirectory: workingDirectory,
         environment: environment,
       ),
       // Keep the public parameter name instead of exposing a private named arg.
       // ignore: prefer_initializing_formals
       _protocolVersion = protocolVersion;

  final JsonRpcClient _rpc;
  final int _protocolVersion;

  StreamSubscription<JsonRpcServerRequest>? _fsSub;
  Map<String, dynamic>? _agentCapabilities;
  final Map<String, String> _cwdBySessionId = <String, String>{};
  var _started = false;
  var _initialized = false;

  /// All notifications coming from the agent (mostly `session/update` plus the
  /// synthetic `alera.stderr` log entries forwarded by [JsonRpcClient]).
  Stream<Map<String, dynamic>> get events => _rpc.notifications;

  /// Server-initiated requests not handled internally (i.e. everything except
  /// the `fs/*` requests, which the client services directly).
  Stream<JsonRpcServerRequest> get requests => _rpc.incomingRequests;

  /// Capabilities returned by the agent during [initialize]. `null` until the
  /// handshake completes.
  Map<String, dynamic>? get agentCapabilities => _agentCapabilities;

  /// Spawns the agent process and attaches the internal `fs/*` handler. Does
  /// NOT perform the protocol handshake — callers must call [initialize]
  /// separately, so they can subscribe to [events] / [requests] before the
  /// agent emits its first message.
  Future<void> start() async {
    if (_started) {
      return;
    }
    try {
      await _rpc.start();
      _fsSub = _rpc.incomingRequests.listen(
        _maybeHandleFs,
        onError: (Object error, StackTrace stackTrace) {
          _rpc.emitSyntheticNotification(
            'alera.fsHandlerError',
            params: <String, dynamic>{
              'error': error.toString(),
              'stackTrace': stackTrace.toString(),
            },
          );
        },
      );
      _started = true;
    } catch (error) {
      // Best-effort cleanup so a half-started client does not leak the
      // spawned process or its broadcast subscription.
      await _fsSub?.cancel();
      _fsSub = null;
      await _rpc.close();
      rethrow;
    }
  }

  /// Performs the ACP `initialize` handshake. Idempotent. Emits a synthetic
  /// `alera.protocolVersionMismatch` notification when the agent's returned
  /// `protocolVersion` differs from the requested one.
  Future<Map<String, dynamic>> initialize() async {
    if (_initialized) {
      return <String, dynamic>{};
    }
    final response = await _rpc.request(
      'initialize',
      params: <String, dynamic>{
        'protocolVersion': _protocolVersion,
        'clientCapabilities': <String, dynamic>{
          'fs': <String, dynamic>{'readTextFile': true, 'writeTextFile': true},
          'terminal': false,
        },
      },
    );
    final result = (response['result'] as Map?)?.cast<String, dynamic>();
    _agentCapabilities = (result?['agentCapabilities'] as Map?)
        ?.cast<String, dynamic>();
    final negotiated = result?['protocolVersion'];
    if (negotiated is num && negotiated.toInt() != _protocolVersion) {
      _rpc.emitSyntheticNotification(
        'alera.protocolVersionMismatch',
        params: <String, dynamic>{
          'requested': _protocolVersion,
          'agentReported': negotiated.toInt(),
        },
      );
    }
    _initialized = true;
    return response;
  }

  /// Starts a new ACP session and returns its `sessionId`. Stores the resolved
  /// absolute cwd by session id so delayed [fs/read_text_file] and
  /// [fs/write_text_file] requests are authorized against their own session.
  Future<String> newSession({required String cwd}) async {
    final response = await _rpc.request(
      'session/new',
      params: <String, dynamic>{
        'cwd': cwd,
        'mcpServers': const <Map<String, dynamic>>[],
      },
    );
    final result = (response['result'] as Map?)?.cast<String, dynamic>();
    final sessionId = _stringOrNull(result?['sessionId']);
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('session/new returned no sessionId');
    }
    _cwdBySessionId[sessionId] = p.normalize(p.absolute(cwd));
    return sessionId;
  }

  /// Resumes a previously created ACP session. Many agents (including current
  /// `codex-acp` builds) do not implement this; callers should fall back to
  /// [newSession] on failure (the orchestrator does so on `StateError`).
  Future<String> loadSession({
    required String sessionId,
    required String cwd,
  }) async {
    final response = await _rpc.request(
      'session/load',
      params: <String, dynamic>{
        'sessionId': sessionId,
        'cwd': cwd,
        'mcpServers': const <Map<String, dynamic>>[],
      },
    );
    final result = (response['result'] as Map?)?.cast<String, dynamic>();
    final resolved = _stringOrNull(result?['sessionId']);
    if (resolved == null || resolved.isEmpty) {
      throw StateError('session/load returned no sessionId');
    }
    _cwdBySessionId[resolved] = p.normalize(p.absolute(cwd));
    return resolved;
  }

  /// Sends a user prompt. Resolves with the agent's `stopReason` once the turn
  /// terminates. Streaming output arrives as `session/update` notifications on
  /// [events] while the future is pending.
  Future<String> prompt({
    required String sessionId,
    required List<Map<String, dynamic>> content,
  }) async {
    final response = await _rpc.request(
      'session/prompt',
      params: <String, dynamic>{'sessionId': sessionId, 'prompt': content},
    );
    final result = (response['result'] as Map?)?.cast<String, dynamic>();
    return _stringOrNull(result?['stopReason']) ?? 'end_turn';
  }

  /// Coerces an `Object?` to a non-empty `String`, returning `null` for any
  /// non-`String` value (including numbers, booleans, maps). Avoids
  /// `value as String?` which throws `TypeError` on non-null, non-String
  /// values.
  static String? _stringOrNull(Object? value) {
    if (value is! String) {
      return null;
    }
    return value.isEmpty ? null : value;
  }

  /// ACP `session/cancel` is a notification (no response expected).
  Future<void> cancel({required String sessionId}) {
    return _rpc.notify(
      'session/cancel',
      params: <String, dynamic>{'sessionId': sessionId},
    );
  }

  /// Responds to a `session/request_permission` request. ACP expects an
  /// `outcome` discriminated union: `{outcome: "selected", optionId: ...}` or
  /// `{outcome: "cancelled"}`.
  Future<void> respondPermission({
    required Object requestId,
    required String optionId,
  }) {
    return _rpc.respondSuccess(
      requestId,
      result: <String, dynamic>{
        'outcome': <String, dynamic>{
          'outcome': 'selected',
          'optionId': optionId,
        },
      },
    );
  }

  Future<void> declinePermission({required Object requestId}) {
    return _rpc.respondSuccess(
      requestId,
      result: <String, dynamic>{
        'outcome': <String, dynamic>{'outcome': 'cancelled'},
      },
    );
  }

  Future<void> respondError({
    required Object requestId,
    required int code,
    required String message,
  }) {
    return _rpc.respondError(id: requestId, code: code, message: message);
  }

  Future<void> close() async {
    await _fsSub?.cancel();
    await _rpc.close();
  }

  /// Handles the `fs/*` server-initiated requests directly via `dart:io` so
  /// the agent can read/write files when its capability negotiation allows it.
  /// Unknown `fs/*` and `terminal/*` methods are rejected with
  /// `methodNotFound` so the agent never deadlocks on an unanswered request.
  void _maybeHandleFs(JsonRpcServerRequest request) {
    final method = request.method;
    switch (method) {
      case 'fs/read_text_file':
        unawaited(_safeFsHandle(_handleFsRead, request));
        return;
      case 'fs/write_text_file':
        unawaited(_safeFsHandle(_handleFsWrite, request));
        return;
      case 'terminal/create':
      case 'terminal/output':
      case 'terminal/wait_for_exit':
      case 'terminal/kill':
      case 'terminal/release':
        unawaited(
          _safeRespondError(
            request,
            code: jsonRpcMethodNotFound,
            message: 'Terminal capability not enabled in this client',
          ),
        );
        return;
    }
    if (method.startsWith('fs/')) {
      unawaited(
        _safeRespondError(
          request,
          code: jsonRpcMethodNotFound,
          message: 'fs method not supported by client: $method',
        ),
      );
    }
  }

  Future<void> _safeFsHandle(
    Future<void> Function(JsonRpcServerRequest) handler,
    JsonRpcServerRequest request,
  ) async {
    try {
      await handler(request);
    } catch (error, stackTrace) {
      // Any leak past the handler's own try/catch (e.g. respondError itself
      // throws because the client closed mid-flight) is logged via the
      // synthetic notification channel instead of being silently discarded
      // by `unawaited`.
      _rpc.emitSyntheticNotification(
        'alera.fsHandlerError',
        params: <String, dynamic>{
          'method': request.method,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  Future<void> _safeRespondError(
    JsonRpcServerRequest request, {
    required int code,
    required String message,
  }) async {
    try {
      await respondError(requestId: request.id, code: code, message: message);
    } catch (error) {
      _rpc.emitSyntheticNotification(
        'alera.fsHandlerError',
        params: <String, dynamic>{
          'method': request.method,
          'error': error.toString(),
        },
      );
    }
  }

  Future<void> _handleFsRead(JsonRpcServerRequest request) async {
    final path = request.params['path'];
    if (path is! String || path.isEmpty) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInvalidParams,
        message: 'fs/read_text_file requires a non-empty "path"',
      );
      return;
    }
    final containmentError = _containmentError(request, path);
    if (containmentError != null) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInvalidParams,
        message: containmentError,
      );
      return;
    }
    final sliceError = _validateSliceParams(
      request.params['line'],
      request.params['limit'],
    );
    if (sliceError != null) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInvalidParams,
        message: sliceError,
      );
      return;
    }
    try {
      final content = await File(path).readAsString();
      final sliced = _sliceByLines(
        content,
        request.params['line'],
        request.params['limit'],
      );
      await _rpc.respondSuccess(
        request.id,
        result: <String, dynamic>{'content': sliced},
      );
    } catch (error) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInternalError,
        message: 'fs/read_text_file failed: $error',
      );
    }
  }

  Future<void> _handleFsWrite(JsonRpcServerRequest request) async {
    final path = request.params['path'];
    final content = request.params['content'];
    if (path is! String || path.isEmpty) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInvalidParams,
        message: 'fs/write_text_file requires a non-empty "path"',
      );
      return;
    }
    if (content is! String) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInvalidParams,
        message: 'fs/write_text_file requires a string "content"',
      );
      return;
    }
    final containmentError = _containmentError(request, path);
    if (containmentError != null) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInvalidParams,
        message: containmentError,
      );
      return;
    }
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      await _rpc.respondSuccess(request.id);
    } catch (error) {
      await respondError(
        requestId: request.id,
        code: jsonRpcInternalError,
        message: 'fs/write_text_file failed: $error',
      );
    }
  }

  /// Returns a human-readable error message when `requested` does not point
  /// inside the request's session cwd, otherwise `null`. Rejects relative paths,
  /// non-absolute paths, unknown sessions, and anything that lexically escapes
  /// the cwd.
  /// Symlink-based escapes are not blocked (documented limitation).
  String? _containmentError(JsonRpcServerRequest request, String requested) {
    final sessionId = _stringOrNull(request.params['sessionId']);
    if (sessionId == null) {
      return 'fs request requires a non-empty "sessionId"';
    }
    final cwd = _cwdBySessionId[sessionId];
    if (cwd == null) {
      return 'fs request received for unknown session: $sessionId';
    }
    if (!p.isAbsolute(requested)) {
      return 'fs path must be absolute: $requested';
    }
    final normalized = p.normalize(requested);
    if (p.equals(normalized, cwd) || p.isWithin(cwd, normalized)) {
      return null;
    }
    return 'fs path outside session workspace ($cwd): $normalized';
  }

  /// Validates `line`/`limit` params for fs/read_text_file. Accepts any
  /// `num` (so JSON-decoded `1.0` works) but rejects fractional, NaN,
  /// non-positive line numbers, and negative limits.
  String? _validateSliceParams(Object? lineParam, Object? limitParam) {
    if (lineParam != null) {
      if (lineParam is! num) {
        return 'fs/read_text_file "line" must be a number';
      }
      if (!lineParam.isFinite || lineParam != lineParam.truncate()) {
        return 'fs/read_text_file "line" must be a whole number';
      }
      if (lineParam.toInt() <= 0) {
        return 'fs/read_text_file "line" must be >= 1';
      }
    }
    if (limitParam != null) {
      if (limitParam is! num) {
        return 'fs/read_text_file "limit" must be a number';
      }
      if (!limitParam.isFinite || limitParam != limitParam.truncate()) {
        return 'fs/read_text_file "limit" must be a whole number';
      }
      if (limitParam.toInt() < 0) {
        return 'fs/read_text_file "limit" must be >= 0';
      }
    }
    return null;
  }

  String _sliceByLines(String content, Object? lineParam, Object? limitParam) {
    if (lineParam is! num && limitParam is! num) {
      return content;
    }
    final lines = content.split('\n');
    final lineCount = lines.length;
    var start = 0;
    if (lineParam is num) {
      final line = lineParam.toInt();
      if (line > lineCount) {
        start = lineCount;
      } else {
        start = line - 1;
      }
    }
    var end = lineCount;
    if (limitParam is num) {
      final limit = limitParam.toInt();
      final upper = start + limit;
      end = upper > lineCount ? lineCount : upper;
    }
    return lines.sublist(start, end).join('\n');
  }
}
