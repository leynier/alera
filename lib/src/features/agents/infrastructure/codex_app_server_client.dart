import 'dart:async';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

class CodexAppServerClient {
  CodexAppServerClient({
    required ProcessRunner processRunner,
    String executable = 'codex',
    List<String> arguments = const <String>[
      'app-server',
      '--listen',
      'stdio://',
    ],
    String? workingDirectory,
    Map<String, String>? environment,
  }) : _client = JsonRpcClient(
         processRunner: processRunner,
         executable: executable,
         arguments: arguments,
         workingDirectory: workingDirectory,
         environment: environment,
       );

  final JsonRpcClient _client;

  Stream<Map<String, dynamic>> get events => _client.notifications;
  Stream<JsonRpcServerRequest> get requests => _client.incomingRequests;

  Future<void> start() async {
    await _client.start();
    await initialize();
    await _client.notify('initialized');
  }

  Future<Map<String, dynamic>> initialize() {
    return _client.request(
      'initialize',
      params: <String, dynamic>{
        'clientInfo': <String, dynamic>{
          'name': 'alera',
          'title': 'Alera Desktop',
          'version': '0.1.0',
        },
        'capabilities': <String, dynamic>{'experimentalApi': true},
      },
    );
  }

  Future<Map<String, dynamic>> listModels() {
    return _client.request('model/list');
  }

  Future<Map<String, dynamic>> startThread({
    String? cwd,
    String? model,
    String approvalPolicy = 'never',
  }) {
    return _client.request(
      'thread/start',
      params: <String, dynamic>{
        ...?cwd == null ? null : <String, dynamic>{'cwd': cwd},
        ...?model == null ? null : <String, dynamic>{'model': model},
        'approvalPolicy': approvalPolicy,
      },
    );
  }

  Future<Map<String, dynamic>> resumeThread(String threadId) {
    return _client.request(
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
    Map<String, dynamic>? collaborationMode,
  }) {
    return _client.request(
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
            : <String, dynamic>{'collaborationMode': collaborationMode},
      },
    );
  }

  Future<Map<String, dynamic>> interruptTurn({
    required String threadId,
    required String turnId,
  }) {
    return _client.request(
      'turn/interrupt',
      params: <String, dynamic>{'threadId': threadId, 'turnId': turnId},
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
    return _client.respondSuccess(requestId, result: result);
  }

  Future<void> respondToolCall({
    required Object requestId,
    required List<Map<String, dynamic>> contentItems,
    bool success = true,
  }) {
    return _client.respondSuccess(
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
    return _client.respondSuccess(requestId, result: <String, dynamic>{
      'answers': answers,
    });
  }

  Future<void> respondError({
    required Object requestId,
    required int code,
    required String message,
  }) {
    return _client.respondError(id: requestId, code: code, message: message);
  }

  Future<void> close() {
    return _client.close();
  }
}
