import 'dart:async';

import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/application/host_routed_ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = AiAssistSettings(enabled: true, timeoutSeconds: 30);

void main() {
  HostRoutedAiAssistService service(
    _FakeRuntimeHostClient client,
    _FakeLocalService local,
  ) => HostRoutedAiAssistService(
    local: local,
    client: client,
    remoteWorkspaceIdFor: (path) =>
        path.startsWith('/srv/') ? 'workspace-remote' : null,
    newOperationId: () => 'operation-1',
  );

  test('a local checkout keeps the desktop implementation', () async {
    final client = _FakeRuntimeHostClient();
    final local = _FakeLocalService();

    final result = await service(client, local).generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/home/me/repo',
        settings: _settings,
      ),
    );

    expect(result.text, 'local text');
    expect(client.types, isEmpty);
  });

  test('a remote commit message is generated on the workspace host', () async {
    final client = _FakeRuntimeHostClient()
      ..response = <String, Object?>{
        'message': 'fix: handle empty input\n',
        'agentLabel': 'Claude',
      };
    final local = _FakeLocalService();

    final result = await service(client, local).generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/srv/repo',
        settings: _settings,
      ),
    );

    expect(result.text, 'fix: handle empty input');
    expect(result.agentLabel, 'Claude');
    expect(local.generated, 0);
    expect(client.types.single, 'aiText.commitMessage.generate');
    expect(client.payloads.single, <String, Object?>{
      'operationId': 'operation-1',
      'workspaceId': 'workspace-remote',
    });
    expect(client.timeouts.single, greaterThan(const Duration(seconds: 30)));
  });

  test('remote pull request details keep the title-then-body shape', () async {
    final client = _FakeRuntimeHostClient()
      ..response = <String, Object?>{
        'title': 'Add remote runner',
        'body': 'Routes forge CLIs.',
        'agentLabel': 'Codex',
      };

    final result = await service(client, _FakeLocalService()).generate(
      const AiAssistRequest(
        operation: AiAssistOperation.pullRequestDetails,
        workspacePath: '/srv/repo',
        settings: _settings,
        baseBranch: ' main ',
      ),
    );

    expect(result.text, 'Add remote runner\n\nRoutes forge CLIs.');
    expect(client.types.single, 'aiText.pullRequestDetails.generate');
    expect(client.payloads.single['baseBranch'], 'main');
  });

  test('cancel follows the generation to the workspace host', () async {
    final gate = Completer<Object?>();
    final client = _FakeRuntimeHostClient()..pending = gate;
    final routed = service(client, _FakeLocalService());

    final generation = routed.generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/srv/repo',
        settings: _settings,
      ),
    );
    await pumpEventQueue();
    routed.cancel('/srv/repo', AiAssistOperation.commitMessage);
    gate.completeError(StateError('Generation canceled.'));

    await expectLater(generation, throwsA(isA<AiAssistCanceledException>()));
    expect(client.types, <String>[
      'aiText.commitMessage.generate',
      'aiText.cancel',
    ]);
    expect(client.payloads.last, <String, Object?>{
      'operationId': 'operation-1',
    });
  });

  test(
    'disabled settings and host failures surface as AI Assist errors',
    () async {
      final client = _FakeRuntimeHostClient()
        ..error = const TerminalHostConflictException(
          code: 'state',
          message: 'claude could not be started.',
        );
      final routed = service(client, _FakeLocalService());

      await expectLater(
        routed.generate(
          const AiAssistRequest(
            operation: AiAssistOperation.commitMessage,
            workspacePath: '/srv/repo',
            settings: AiAssistSettings(enabled: false),
          ),
        ),
        throwsA(isA<AiAssistException>()),
      );
      expect(client.types, isEmpty);
      await expectLater(
        routed.generate(
          const AiAssistRequest(
            operation: AiAssistOperation.commitMessage,
            workspacePath: '/srv/repo',
            settings: _settings,
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            contains('could not be started'),
          ),
        ),
      );
    },
  );
}

final class _FakeLocalService implements AiAssistService {
  int generated = 0;
  final canceled = <String>[];

  @override
  Future<AiAssistResult> generate(AiAssistRequest request) async {
    generated++;
    return const AiAssistResult(text: 'local text', agentLabel: 'Local');
  }

  @override
  void cancel(String workspacePath, AiAssistOperation operation) {
    canceled.add(workspacePath);
  }
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  Object? response;
  Object? error;
  Completer<Object?>? pending;
  final types = <String>[];
  final payloads = <Map<String, Object?>>[];
  final timeouts = <Duration?>[];
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    types.add(type);
    payloads.add(payload);
    timeouts.add(timeout);
    if (type == 'aiText.cancel') {
      return <String, Object?>{'canceled': true};
    }
    if (pending case final gate?) {
      return gate.future;
    }
    if (error case final failure?) {
      throw failure;
    }
    return response;
  }
}
