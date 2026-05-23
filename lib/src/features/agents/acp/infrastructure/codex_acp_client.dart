import 'dart:async';
import 'dart:io';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_error_codes.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// Thin client over the Agent Client Protocol (ACP) — speaks newline-delimited
/// JSON-RPC 2.0 over the spawned agent's stdio. Built on top of the shared
/// [JsonRpcClient] so all framing, request/response correlation, and stderr
/// forwarding behave the same as the existing Codex app-server transport.
///
/// Mirrors the public surface of `CodexAppServerClient` where ACP has a direct
/// equivalent (initialize, session/new, session/load, session/prompt,
/// session/cancel) and stubs the rest as `UnsupportedError` so callers fail
/// loudly when a Codex-only feature is requested through the ACP path.
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

  /// All notifications coming from the agent (mostly `session/update` plus the
  /// synthetic `alera.stderr` log entries forwarded by [JsonRpcClient]).
  Stream<Map<String, dynamic>> get events => _rpc.notifications;

  /// Server-initiated requests not handled internally (i.e. everything except
  /// the `fs/*` requests, which the client services directly).
  Stream<JsonRpcServerRequest> get requests => _rpc.incomingRequests;

  /// Capabilities returned by the agent during [initialize]. `null` until the
  /// handshake completes.
  Map<String, dynamic>? get agentCapabilities => _agentCapabilities;

  Future<void> start() async {
    await _rpc.start();
    _fsSub = _rpc.incomingRequests.listen(_maybeHandleFs);
    await initialize();
  }

  Future<Map<String, dynamic>> initialize() async {
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
    return response;
  }

  /// Starts a new ACP session and returns its `sessionId`.
  Future<String> newSession({required String cwd}) async {
    final response = await _rpc.request(
      'session/new',
      params: <String, dynamic>{
        'cwd': cwd,
        'mcpServers': const <Map<String, dynamic>>[],
      },
    );
    final result = (response['result'] as Map?)?.cast<String, dynamic>();
    final sessionId = result?['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('session/new returned no sessionId');
    }
    return sessionId;
  }

  /// Resumes a previously created ACP session. Many agents (including current
  /// `codex-acp` builds) do not implement this; callers should fall back to
  /// [newSession] on failure.
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
    return (result?['sessionId'] as String?) ?? sessionId;
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
    return (result?['stopReason'] as String?) ?? 'end_turn';
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
  /// Returns silently for any other method (orchestrator handles those).
  void _maybeHandleFs(JsonRpcServerRequest request) {
    switch (request.method) {
      case 'fs/read_text_file':
        unawaited(_handleFsRead(request));
        return;
      case 'fs/write_text_file':
        unawaited(_handleFsWrite(request));
        return;
      case 'terminal/create':
      case 'terminal/output':
      case 'terminal/wait_for_exit':
      case 'terminal/kill':
      case 'terminal/release':
        unawaited(
          respondError(
            requestId: request.id,
            code: jsonRpcMethodNotFound,
            message: 'Terminal capability not enabled in this client',
          ),
        );
        return;
    }
  }

  Future<void> _handleFsRead(JsonRpcServerRequest request) async {
    try {
      final path = request.params['path'];
      if (path is! String || path.isEmpty) {
        await respondError(
          requestId: request.id,
          code: jsonRpcInvalidParams,
          message: 'fs/read_text_file requires a non-empty "path"',
        );
        return;
      }
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
    try {
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

  String _sliceByLines(String content, Object? lineParam, Object? limitParam) {
    if (lineParam is! int && limitParam is! int) {
      return content;
    }
    final lines = content.split('\n');
    final lineCount = lines.length;
    var start = 0;
    if (lineParam is int) {
      if (lineParam <= 1) {
        start = 0;
      } else if (lineParam > lineCount) {
        start = lineCount;
      } else {
        start = lineParam - 1;
      }
    }
    var end = lineCount;
    if (limitParam is int && limitParam >= 0) {
      final upper = start + limitParam;
      end = upper > lineCount ? lineCount : upper;
    }
    return lines.sublist(start, end).join('\n');
  }
}
