import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

Map<String, Object?> _operation() => <String, Object?>{
  'operationId': 'op',
  'state': 'uncertain',
  'kind': 'rewindFiles',
  'nativeAck': <String, Object?>{'token': 'must-not-survive'},
  'nativeThreadId': 'must-not-survive',
  'recovery': <String, Object?>{
    'needsReconciliation': true,
    'canCancelUnstarted': false,
    'canFinishAcknowledged': false,
    'canRestartFromTranscript': false,
    'canContinueFromCurrentFiles': true,
    'message': 'Review the current files before continuing.',
    'rawError': 'must-not-survive',
  },
};

void main() {
  test('pending native projection retains only public operation and recovery fields', () {
    final snapshot = AgentChatSnapshot.fromJson(<String, Object?>{
      ...agentChatContractSnapshot(),
      'pendingNativeOperation': _operation(),
    });
    final operation = snapshot.pendingNativeOperation!;
    expect(operation.toJson().keys, <String>[
      'operationId',
      'state',
      'kind',
      'recovery',
    ]);
    expect(operation.recovery?.canContinueFromCurrentFiles, isTrue);
    expect(operation.recovery!.toJson().keys, <String>[
      'needsReconciliation',
      'canCancelUnstarted',
      'canFinishAcknowledged',
      'canRestartFromTranscript',
      'canContinueFromCurrentFiles',
      'message',
    ]);
    expect(snapshot.neverSent, isFalse);
    expect(
      snapshot.copyWith(cursor: 4).pendingNativeOperation?.operationId,
      'op',
    );
  });

  test('shared reducer preserves omitted pending operations and clears explicit null', () {
    var thread = AgentChatThread.fromSnapshot(
      AgentChatSnapshot.fromJson(<String, Object?>{
        ...agentChatContractSnapshot(),
        'pendingNativeOperation': _operation(),
      }),
    );
    final unchanged = AgentChatChange.fromJson(<String, Object?>{
      'chatId': 'c',
      'cursor': 4,
      'delta': <String, Object?>{'title': 'Changed'},
    });
    expect(unchanged.hasPendingNativeOperation, isFalse);
    thread = (thread.apply(unchanged) as AgentChatApplied).thread;
    expect(thread.pendingNativeOperation?.operationId, 'op');
    final cleared = AgentChatChange.fromJson(<String, Object?>{
      'chatId': 'c',
      'cursor': 5,
      'delta': <String, Object?>{'pendingNativeOperation': null},
    });
    expect(cleared.hasPendingNativeOperation, isTrue);
    thread = (thread.apply(cleared) as AgentChatApplied).thread;
    expect(thread.pendingNativeOperation, isNull);
  });

  test('invalid operation projections require stream resync rather than clearing pending state', () async {
    final transport = AgentChatContractTransport();
    addTearDown(transport.controller.close);
    final received = <AgentChatStreamEvent>[];
    final subscription = RuntimeAgentChatRepository(transport)
        .watch('c')
        .listen(received.add);
    transport.controller.add(
      const AgentChatTransportEvent(
        AgentChatWire.changedEvent,
        <String, Object?>{
          'chatId': 'c',
          'cursor': 4,
          'delta': <String, Object?>{'pendingNativeOperation': <String>[]},
        },
      ),
    );
    await Future.pause(Duration.zero);
    await subscription.cancel();
    expect(received.single, isA<AgentChatResyncRequired>());
  });
}
