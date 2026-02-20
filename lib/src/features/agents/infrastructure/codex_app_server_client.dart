import 'dart:async';

import 'package:alera/src/shared/infra/json_rpc/json_rpc_client.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/models/contracts.dart';

class CodexAppServerClient {
  CodexAppServerClient({
    required ProcessRunner processRunner,
    String executable = 'codex',
    List<String> arguments = const <String>['app-server', '--listen', 'stdio://'],
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
        'capabilities': <String, dynamic>{
          'experimentalApi': true,
        },
      },
    );
  }

  Future<Map<String, dynamic>> listModels() {
    return _client.request('model/list');
  }

  Future<Map<String, dynamic>> listCollaborationModes() {
    return _client.request('collaborationMode/list');
  }

  Future<Map<String, dynamic>> startThread({
    String? cwd,
    String? model,
    String? approvalPolicy,
  }) {
    return _client.request(
      'thread/start',
      params: <String, dynamic>{
        ...?cwd == null ? null : <String, dynamic>{'cwd': cwd},
        ...?model == null ? null : <String, dynamic>{'model': model},
        ...?approvalPolicy == null
            ? null
            : <String, dynamic>{'approvalPolicy': approvalPolicy},
      },
    );
  }

  Future<Map<String, dynamic>> resumeThread(String threadId) {
    return _client.request(
      'thread/resume',
      params: <String, dynamic>{'threadId': threadId},
    );
  }

  Future<Map<String, dynamic>> forkThread(String threadId) {
    return _client.request(
      'thread/fork',
      params: <String, dynamic>{'threadId': threadId},
    );
  }

  Future<Map<String, dynamic>> startTurn({
    required String threadId,
    required List<Map<String, dynamic>> input,
    String? model,
    String? cwd,
    String? approvalPolicy,
    String? collaborationMode,
  }) {
    return _client.request(
      'turn/start',
      params: <String, dynamic>{
        'threadId': threadId,
        'input': input,
        ...?model == null ? null : <String, dynamic>{'model': model},
        ...?cwd == null ? null : <String, dynamic>{'cwd': cwd},
        ...?approvalPolicy == null
            ? null
            : <String, dynamic>{'approvalPolicy': approvalPolicy},
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
      params: <String, dynamic>{
        'threadId': threadId,
        'turnId': turnId,
      },
    );
  }

  Future<Map<String, dynamic>> reviewStart(
    String threadId, {
    String delivery = 'inline',
    Map<String, dynamic>? target,
  }) {
    return _client.request(
      'review/start',
      params: <String, dynamic>{
        'threadId': threadId,
        'delivery': delivery,
        'target': target ?? const <String, dynamic>{'type': 'uncommittedChanges'},
      },
    );
  }

  Future<Map<String, dynamic>> mcpServerStatusList() {
    return _client.request('mcpServerStatus/list');
  }

  Future<Map<String, dynamic>> mcpServerOauthLogin(String name) {
    return _client.request(
      'mcpServer/oauth/login',
      params: <String, dynamic>{'name': name},
    );
  }

  Future<Map<String, dynamic>> configRead() {
    return _client.request('config/read');
  }

  Future<Map<String, dynamic>> configValueWrite({
    required String key,
    required Object? value,
  }) {
    return _client.request(
      'config/value/write',
      params: <String, dynamic>{
        'key': key,
        'value': value,
      },
    );
  }

  Future<Map<String, dynamic>> configBatchWrite({
    required List<Map<String, dynamic>> updates,
  }) {
    return _client.request(
      'config/batchWrite',
      params: <String, dynamic>{
        'updates': updates,
      },
    );
  }

  Future<Map<String, dynamic>> configMcpServerReload() {
    return _client.request('config/mcpServer/reload');
  }

  Future<void> respondApproval({
    required Object requestId,
    required ApprovalDecisionType decision,
    AllowScope? allowScope,
  }) {
    final result = <String, dynamic>{
      'decision': decision == ApprovalDecisionType.accept ? 'accept' : 'decline',
    };

    if (decision == ApprovalDecisionType.accept && allowScope == AllowScope.session) {
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
