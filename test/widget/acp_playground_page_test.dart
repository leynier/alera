import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agents/acp/presentation/acp_playground_page.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fileSelectorChannel = MethodChannel('plugins.flutter.io/file_selector');

  testWidgets('cancel turn cancels pending ACP permission requests', (
    tester,
  ) async {
    final workspace = Directory(
      '${Directory.systemTemp.path}/alera_acp_widget_test',
    )..createSync(recursive: true);
    addTearDown(() {
      if (workspace.existsSync()) {
        workspace.deleteSync(recursive: true);
      }
    });

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fileSelectorChannel,
      (call) async {
        if (call.method == 'getDirectoryPath') {
          return workspace.path;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        fileSelectorChannel,
        null,
      ),
    );

    final processRunner = _FakeAcpProcessRunner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [processRunnerProvider.overrideWith((ref) => processRunner)],
        child: const MaterialApp(home: AcpPlaygroundPage()),
      ),
    );

    await tester.tap(find.text('Choose folder'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Start session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    processRunner.process.sendServerRequest(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'permission-1',
      'method': 'session/request_permission',
      'params': <String, dynamic>{
        'sessionId': 'session-1',
        'toolCall': <String, dynamic>{'title': 'Run command'},
        'options': <Map<String, dynamic>>[
          <String, dynamic>{'optionId': 'allow_once', 'name': 'Allow once'},
        ],
      },
    });
    await tester.pump();
    expect(find.text('Permission requested'), findsOneWidget);

    await tester.tap(find.text('Cancel turn'));
    await tester.pump();

    final permissionResponse =
        processRunner.process.responsesById['permission-1'];
    expect(permissionResponse, isNotNull);
    expect(permissionResponse!['result'], <String, dynamic>{
      'outcome': <String, dynamic>{'outcome': 'cancelled'},
    });
    expect(processRunner.process.cancelledSessions, <String>['session-1']);
    expect(find.text('Permission requested'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeAcpProcessRunner implements ProcessRunner {
  _FakeAcpProcessRunner() : process = _FakeAcpProcess();

  final _FakeAcpProcess process;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return process.startedProcess;
  }
}

class _FakeAcpProcess {
  final StreamController<List<int>> _stdout =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderr =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCode = Completer<int>();

  final Map<Object, Map<String, dynamic>> responsesById =
      <Object, Map<String, dynamic>>{};
  final List<String> cancelledSessions = <String>[];
  String _stdinBuffer = '';

  StartedProcess get startedProcess => StartedProcess(
    stdinWrite: _stdinWrite,
    stdout: _stdout.stream,
    stderr: _stderr.stream,
    pid: 1001,
    exitCode: _exitCode.future,
    kill: ([signal]) {
      if (!_exitCode.isCompleted) {
        _exitCode.complete(0);
      }
      unawaited(_stdout.close());
      unawaited(_stderr.close());
      return true;
    },
  );

  void sendServerRequest(Map<String, dynamic> message) {
    _stdout.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  void _stdinWrite(List<int> data) {
    _stdinBuffer += utf8.decode(data);
    while (_stdinBuffer.contains('\n')) {
      final index = _stdinBuffer.indexOf('\n');
      final rawLine = _stdinBuffer.substring(0, index).trim();
      _stdinBuffer = _stdinBuffer.substring(index + 1);
      if (rawLine.isEmpty) {
        continue;
      }
      final message = jsonDecode(rawLine) as Map<String, dynamic>;
      _handleClientMessage(message);
    }
  }

  void _handleClientMessage(Map<String, dynamic> message) {
    final id = message['id'];
    final method = message['method'];
    final params = (message['params'] as Map?)?.cast<String, dynamic>();

    if (method == 'initialize') {
      sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'protocolVersion': 1,
          'agentCapabilities': <String, dynamic>{},
        },
      });
      return;
    }

    if (method == 'session/new') {
      sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'sessionId': 'session-1'},
      });
      return;
    }

    if (method == 'session/cancel') {
      final sessionId = params?['sessionId'];
      if (sessionId is String) {
        cancelledSessions.add(sessionId);
      }
      return;
    }

    if (id != null &&
        (message.containsKey('result') || message.containsKey('error'))) {
      responsesById[id] = message;
    }
  }
}
