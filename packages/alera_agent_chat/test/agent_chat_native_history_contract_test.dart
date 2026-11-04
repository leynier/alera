import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');

final class _LegacyLifecycle extends AgentChatLifecycleRepository {
  @override
  Future<AgentChatRewindResult> rewind(
    AgentChatRef chat, {
    required String requestId,
    required String turnId,
  }) async => const AgentChatRewindResult(
    snapshot: AgentChatSnapshot(chatId: 'c', workspaceId: 'w', cursor: 0),
    prompt: 'Original',
  );
}

void main() {
  late AgentChatContractTransport transport;
  late AgentChatNativeHistoryRepository repository;
  setUp(() {
    transport = AgentChatContractTransport();
    repository = RuntimeAgentChatLifecycleRepository(transport).nativeHistory;
  });
  tearDown(() => transport.controller.close());

  test(
    'legacy lifecycle fakes keep their transcript rewind signature',
    () async {
      final legacy = _LegacyLifecycle();
      expect(
        (await legacy.rewind(
          _chat,
          requestId: 'r',
          turnId: 't',
        )).filesystemChangesReverted,
        isFalse,
      );
      expect(
        await legacy.nativeHistory.supports(
          AgentChatWire.nativeHistoryCapability,
        ),
        isFalse,
      );
      await expectLater(
        legacy.nativeHistory.rewind(
          _chat,
          requestId: 'r',
          turnId: 't',
          mode: .native,
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('default transcript rewind preserves the original payload and false filesystem result', () async {
    transport.capabilities.add(AgentChatWire.rewindCapability);
    transport.responses[AgentChatWire.rewind] = <String, Object?>{
      'snapshot': agentChatContractSnapshot(),
      'prompt': 'Original',
    };
    final result = await repository.rewind(_chat, requestId: 'r', turnId: 't');
    expect(result.filesystemChangesReverted, isFalse);
    expect(result.filesystemRewindAcknowledged, isFalse);
    expect(transport.requests.single.$2, <String, Object?>{
      'chatId': 'c',
      'workspaceId': 'w',
      'requestId': 'r',
      'turnId': 't',
    });
  });

  test('native rewind needs its own capability and acknowledgement does not prove file reversal', () async {
    transport.capabilities.add(AgentChatWire.rewindCapability);
    await expectLater(
      repository.rewind(_chat, requestId: 'r', turnId: 't', mode: .native),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
    transport.capabilities.add(AgentChatWire.nativeRewindCapability);
    transport.responses[AgentChatWire.rewind] = <String, Object?>{
      'snapshot': agentChatContractSnapshot(),
      'prompt': 'Original',
      'filesystemRewindAcknowledged': true,
    };
    final result = await repository.rewind(
      _chat,
      requestId: 'r',
      turnId: 't',
      mode: .native,
    );
    expect(result.filesystemRewindAcknowledged, isTrue);
    expect(result.filesystemChangesReverted, isNull);
    expect(transport.requests.single.$2['mode'], 'native');
  });

  test(
    'file rewind retains only explicitly reported filesystem observations',
    () async {
      await expectLater(
        repository.rewindFiles(_chat, requestId: 'r', turnId: 't'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(transport.requests, isEmpty);
      transport.capabilities.add(AgentChatWire.rewindFilesCapability);
      transport.responses[AgentChatWire.rewindFiles] = <String, Object?>{
        'operationId': 'op',
        'filesystemRewindAcknowledged': true,
      };
      final result = await repository.rewindFiles(
        _chat,
        requestId: 'r',
        turnId: 't',
      );
      expect(result.filesystemRewindAcknowledged, isTrue);
      expect(result.filesystemChangesReverted, isNull);
      expect(result.operationId, 'op');
      expect(
        AgentChatFilesystemRewindResult.fromJson(<String, Object?>{
          'filesystemChangesReverted': true,
        }).filesystemChangesReverted,
        isTrue,
      );
      expect(
        AgentChatFilesystemRewindResult.fromJson(<String, Object?>{
          'filesystemChangesReverted': 'true',
        }).filesystemChangesReverted,
        isNull,
      );
      expect(transport.requests.single.$1, AgentChatWire.rewindFiles);
    },
  );

  test(
    'checkpoint support is distinct from enabled state and dynamic file rewind',
    () async {
      const sessionJson = <String, Object?>{
        'fileCheckpointing': false,
        'capabilities': <String, Object?>{
          'nativeHistory': <String, Object?>{
            'fileCheckpointing': true,
            'rewindFiles': false,
          },
        },
      };
      final session = AgentChatSession.fromJson(sessionJson);
      expect(session.fileCheckpointing, isFalse);
      expect(session.capabilities.nativeHistory.fileCheckpointing, isTrue);
      expect(session.capabilities.nativeHistory.rewindFiles, isFalse);
      await expectLater(
        repository.configureFileCheckpoints(
          _chat,
          requestId: 'r',
          enabled: true,
        ),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      transport.capabilities.add(AgentChatWire.fileCheckpointsCapability);
      transport.responses[AgentChatWire.fileCheckpointsConfigure] =
          <String, Object?>{
            'snapshot': <String, Object?>{
              ...agentChatContractSnapshot(),
              'session': <String, Object?>{
                ...sessionJson,
                'fileCheckpointing': true,
              },
            },
          };
      final snapshot = await repository.configureFileCheckpoints(
        _chat,
        requestId: 'r',
        enabled: true,
      );
      expect(snapshot.session.fileCheckpointing, isTrue);
      expect(transport.requests.single.$2['enabled'], isTrue);
    },
  );

  test('reconciliation is guarded and carries exact public action names with optional revision', () async {
    await expectLater(
      repository.reconcile(
        _chat,
        requestId: 'r',
        operationId: 'op',
        action: .finishAcknowledged,
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
    transport.capabilities.add(AgentChatWire.nativeHistoryCapability);
    transport.responses[AgentChatWire.nativeHistoryReconcile] =
        <String, Object?>{
          'snapshot': agentChatContractSnapshot(),
          'operation': <String, Object?>{
            'operationId': 'op',
            'state': 'completed',
            'kind': 'rewindFiles',
          },
          'result': <String, Object?>{
            'filesystemRewindAcknowledged': true,
            'filesystemChangesReverted': null,
            'nativeAck': <String, Object?>{'token': 'must-not-survive'},
          },
        };
    for (final action in AgentChatNativeHistoryAction.values) {
      final result = await repository.reconcile(
        _chat,
        requestId: action.wire,
        operationId: 'op',
        action: action,
      );
      expect(transport.requests.last.$2['action'], action.wire);
      expect(
        transport.requests.last.$2.containsKey('expectedRevision'),
        isFalse,
      );
      expect(result.result?.filesystemChangesReverted, isNull);
      expect(result.result?.filesystemRewindAcknowledged, isTrue);
    }
    await repository.reconcile(
      _chat,
      requestId: 'cas',
      operationId: 'op',
      action: .continueFromCurrentFiles,
      expectedRevision: 7,
    );
    expect(transport.requests.last.$2['expectedRevision'], 7);
    expect(transport.requests.last.$2['action'], 'continueFromCurrentFiles');
  });

  test('status read uses the public operation verb without exposing raw native metadata', () async {
    transport.capabilities.add(AgentChatWire.nativeHistoryCapability);
    transport.responses[AgentChatWire.nativeHistoryOperation] =
        <String, Object?>{'operation': null};
    expect(await repository.operation(_chat), isNull);
    expect(transport.requests.single.$2.containsKey('operationId'), isFalse);
    transport.responses[AgentChatWire.nativeHistoryOperation] =
        <String, Object?>{
          'operation': <String, Object?>{
            'operationId': 'op',
            'state': 'uncertain',
            'kind': 'rewindFiles',
            'acknowledgement': 'must-not-survive',
          },
        };
    final operation = await repository.operation(_chat, operationId: 'op');
    expect(operation?.toJson(), <String, Object?>{
      'operationId': 'op',
      'state': 'uncertain',
      'kind': 'rewindFiles',
    });
    expect(transport.requests.last.$2['operationId'], 'op');
  });
}
