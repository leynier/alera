import 'dart:async';
import 'dart:convert';

import 'package:alera/src/shared/models/contracts.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_websocket_client.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// Matches the WebSocket listen address printed on `stderr` by the Codex
/// `app-server` when started with `--listen ws://127.0.0.1:0`.
final _wsListenRegex = RegExp(r'ws://127\.0\.0\.1:(\d+)');

class CodexAppServerClient {
  CodexAppServerClient({
    required ProcessRunner processRunner,
    String executable = 'codex',
    List<String> arguments = const <String>[
      'app-server',
      '--listen',
      'ws://127.0.0.1:0',
    ],
    String? workingDirectory,
    Map<String, String>? environment,
  }) : _processRunner = processRunner,
       _executable = executable,
       _arguments = arguments,
       _workingDirectory = workingDirectory,
       _environment = environment;

  final ProcessRunner _processRunner;
  final String _executable;
  final List<String> _arguments;
  final String? _workingDirectory;
  final Map<String, String>? _environment;

  JsonRpcWebSocketClient? _wsClient;
  StartedProcess? _process;

  final StreamController<Map<String, dynamic>> _stderrController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events {
    final ws = _wsClient;
    if (ws == null) {
      return _stderrController.stream;
    }
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    ws.notifications.listen(controller.add, onError: controller.addError);
    _stderrController.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    return controller.stream;
  }

  Stream<JsonRpcServerRequest> get requests {
    final ws = _wsClient;
    if (ws == null) {
      return const Stream.empty();
    }
    return ws.incomingRequests;
  }

  Future<void> start() async {
    _process = await _processRunner.start(
      _executable,
      _arguments,
      workingDirectory: _workingDirectory,
      environment: _environment,
    );

    final port = await _waitForWebSocketPort(_process!);

    _wsClient = JsonRpcWebSocketClient(Uri.parse('ws://127.0.0.1:$port'));
    await _wsClient!.connect();

    await initialize();
    await _wsClient!.notify('initialized');
  }

  /// Reads `stderr` from the spawned process until the WebSocket listen banner
  /// is found. Returns the dynamically assigned port number.
  ///
  /// All `stderr` output is forwarded as `alera.stderr` notifications so the
  /// UI can still display server logs.
  Future<int> _waitForWebSocketPort(StartedProcess process) {
    final completer = Completer<int>();
    final buffer = StringBuffer();

    late final StreamSubscription<List<int>> sub;
    sub = process.stderr.listen(
      (data) {
        final text = utf8.decode(data, allowMalformed: true);
        buffer.write(text);

        // Forward as notification for log visibility.
        _stderrController.add(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'alera.stderr',
          'params': <String, dynamic>{'data': text},
        });

        if (!completer.isCompleted) {
          final match = _wsListenRegex.firstMatch(buffer.toString());
          if (match != null) {
            completer.complete(int.parse(match.group(1)!));
          }
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    // Fail if the process exits before we find the port.
    unawaited(
      process.exitCode.then((code) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(
              'Codex app-server exited with code $code before advertising '
              'WebSocket port',
            ),
          );
        }
      }),
    );

    // Safety timeout in case the banner never appears.
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        sub.cancel();
        throw TimeoutException(
          'Timed out waiting for Codex app-server WebSocket port',
        );
      },
    );
  }

  Future<Map<String, dynamic>> initialize() {
    return _wsClient!.request(
      'initialize',
      params: <String, dynamic>{
        'clientInfo': <String, dynamic>{
          'name': 'Alera',
          'title': 'Alera Desktop',
          'version': '0.1.0',
        },
        'capabilities': <String, dynamic>{'experimentalApi': true},
      },
    );
  }

  Future<Map<String, dynamic>> listModels() {
    return _wsClient!.request('model/list');
  }

  Future<List<CodexCollaborationModePreset>> listCollaborationModes() async {
    final result = await _requestResult(
      'collaborationMode/list',
      params: const <String, dynamic>{},
    );
    final data = result['data'];
    if (data is! List) {
      throw StateError('collaborationMode/list result is missing data');
    }
    return data
        .whereType<Map>()
        .map(
          (item) => CodexCollaborationModePreset.fromJson(
            item.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<CodexSkillsListEntry>> listSkills({
    List<String>? cwds,
    bool forceReload = false,
    List<CodexSkillsListExtraRootsForCwd>? perCwdExtraUserRoots,
  }) async {
    final result = await _requestResult(
      'skills/list',
      params: <String, dynamic>{
        ...?cwds == null ? null : <String, dynamic>{'cwds': cwds},
        'forceReload': forceReload,
        ...?perCwdExtraUserRoots == null
            ? null
            : <String, dynamic>{
                'perCwdExtraUserRoots': perCwdExtraUserRoots
                    .map((entry) => entry.toJson())
                    .toList(growable: false),
              },
      },
    );
    final data = result['data'];
    if (data is! List) {
      throw StateError('skills/list result is missing data');
    }
    return data
        .whereType<Map>()
        .map(
          (item) => CodexSkillsListEntry.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<CodexAppsPage> listApps({
    String? cursor,
    int? limit,
    String? threadId,
    bool forceRefetch = false,
  }) async {
    final result = await _requestResult(
      'app/list',
      params: <String, dynamic>{
        'cursor': cursor,
        'limit': limit,
        'threadId': threadId,
        'forceRefetch': forceRefetch,
      },
    );
    return CodexAppsPage.fromJson(result);
  }

  Future<Map<String, dynamic>> startThread({
    String? cwd,
    String? model,
    String approvalPolicy = 'never',
  }) {
    return _wsClient!.request(
      'thread/start',
      params: <String, dynamic>{
        ...?cwd == null ? null : <String, dynamic>{'cwd': cwd},
        ...?model == null ? null : <String, dynamic>{'model': model},
        'approvalPolicy': approvalPolicy,
      },
    );
  }

  Future<Map<String, dynamic>> resumeThread(String threadId) {
    return _wsClient!.request(
      'thread/resume',
      params: <String, dynamic>{'threadId': threadId},
    );
  }

  Future<Map<String, dynamic>> startTurn({
    required String threadId,
    required List<Map<String, dynamic>> input,
    required String model,
    required String reasoningEffort,
    String? cwd,
    String approvalPolicy = 'never',
    CodexCollaborationMode? collaborationMode,
  }) {
    return _wsClient!.request(
      'turn/start',
      params: <String, dynamic>{
        'threadId': threadId,
        'input': input,
        'model': model,
        'reasoning': <String, dynamic>{'effort': reasoningEffort},
        ...?cwd == null ? null : <String, dynamic>{'cwd': cwd},
        'approvalPolicy': approvalPolicy,
        ...?collaborationMode == null
            ? null
            : <String, dynamic>{
                'collaborationMode': collaborationMode.toJson(),
              },
      },
    );
  }

  Future<CodexReviewStartResult> startReview({
    required String threadId,
    required CodexReviewTarget target,
    CodexReviewDelivery? delivery,
  }) async {
    final result = await _requestResult(
      'review/start',
      params: <String, dynamic>{
        'threadId': threadId,
        'target': target.toJson(),
        ...?delivery == null
            ? null
            : <String, dynamic>{'delivery': delivery.wireValue},
      },
    );
    return CodexReviewStartResult.fromJson(result);
  }

  Future<void> setThreadName({
    required String threadId,
    required String name,
  }) async {
    await _requestResult(
      'thread/name/set',
      params: <String, dynamic>{'threadId': threadId, 'name': name},
    );
  }

  Future<Map<String, dynamic>> interruptTurn({
    required String threadId,
    required String turnId,
  }) {
    return _wsClient!.request(
      'turn/interrupt',
      params: <String, dynamic>{'threadId': threadId, 'turnId': turnId},
    );
  }

  /// Requests manual context compaction for the given thread.
  Future<Map<String, dynamic>> compactThread({required String threadId}) {
    return _wsClient!.request(
      'thread/compact/start',
      params: <String, dynamic>{'threadId': threadId},
    );
  }

  /// Steers an active turn with new input, redirecting the agent mid-turn.
  Future<Map<String, dynamic>> steerTurn({
    required String threadId,
    required List<Map<String, dynamic>> input,
    required String expectedTurnId,
  }) {
    return _wsClient!.request(
      'turn/steer',
      params: <String, dynamic>{
        'threadId': threadId,
        'input': input,
        'expectedTurnId': expectedTurnId,
      },
    );
  }

  Future<void> respondApproval({
    required Object requestId,
    String decision = 'accept',
    bool forSession = false,
  }) {
    final result = <String, dynamic>{'decision': decision};
    if (decision == 'accept' && forSession) {
      result['acceptSettings'] = <String, dynamic>{'forSession': true};
    }
    return _wsClient!.respondSuccess(requestId, result: result);
  }

  Future<void> respondToolCall({
    required Object requestId,
    required List<Map<String, dynamic>> contentItems,
    bool success = true,
  }) {
    return _wsClient!.respondSuccess(
      requestId,
      result: <String, dynamic>{
        'contentItems': contentItems,
        'success': success,
      },
    );
  }

  Future<void> respondUserInput({
    required Object requestId,
    required Map<String, dynamic> answers,
  }) {
    return _wsClient!.respondSuccess(
      requestId,
      result: <String, dynamic>{'answers': answers},
    );
  }

  Future<void> respondError({
    required Object requestId,
    required int code,
    required String message,
  }) {
    return _wsClient!.respondError(id: requestId, code: code, message: message);
  }

  Future<void> close() async {
    await _wsClient?.close();
    _process?.kill();
    await _stderrController.close();
  }

  Future<Map<String, dynamic>> _requestResult(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _wsClient!.request(method, params: params);
    final result = response['result'];
    if (result is! Map<String, dynamic>) {
      throw StateError('$method returned no result object');
    }
    return result;
  }
}
