import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final class _FakeTransport implements AgentChatTransport {
  _FakeTransport({this.capable = true});

  bool capable;
  final List<(String, Map<String, Object?>, Duration?)> requests =
      <(String, Map<String, Object?>, Duration?)>[];
  final Map<String, Map<String, Object?>> responses =
      <String, Map<String, Object?>>{};
  final StreamController<AgentChatTransportEvent> controller =
      StreamController<AgentChatTransportEvent>.broadcast();

  @override
  Stream<AgentChatTransportEvent> get events => controller.stream;

  @override
  Future<bool> supportsCapability(String capability) async =>
      capable && capability == AgentChatWire.capability;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload, timeout));
    return responses[type] ?? const <String, Object?>{};
  }
}

const _chat = AgentChatRef(chatId: 'chat-1', workspaceId: 'ws-1');

Map<String, Object?> _snapshotJson() => <String, Object?>{
  'chatId': 'chat-1',
  'workspaceId': 'ws-1',
  'tabId': 'tab-1',
  'cursor': 3,
  'provider': 'codex',
  'providerInstanceId': 'codex',
};

void main() {
  test('fails closed without the capability and sends nothing', () async {
    final transport = _FakeTransport(capable: false);
    final repository = RuntimeAgentChatRepository(transport);
    expect(await repository.supported(), isFalse);
    await expectLater(
      repository.snapshot(_chat),
      throwsA(isA<AgentChatUpdateRequired>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('chat-scoped verbs carry chat, workspace and request ids', () async {
    final transport = _FakeTransport()
      ..responses[AgentChatWire.configure] = <String, Object?>{
        'snapshot': _snapshotJson(),
      }
      ..responses[AgentChatWire.queueCancel] = <String, Object?>{
        'cancelled': true,
      };
    final repository = RuntimeAgentChatRepository(transport);
    await repository.respond(
      _chat,
      requestId: 'req-1',
      runtimeRequestId: 'rt-9',
      response: const AgentChatUserInputResponse(<String, List<String>>{
        'scope': <String>['all', 'and tests'],
      }),
    );
    final snapshot = await repository.configure(
      _chat,
      requestId: 'req-2',
      configuration: const AgentChatConfiguration(
        provider: 'claudeAgent',
        runtimeMode: AgentChatRuntimeMode.autoAcceptEdits,
      ),
    );
    final cancelled = await repository.cancelQueued(
      _chat,
      requestId: 'req-3',
      queueId: 'q-1',
    );
    expect(snapshot.cursor, 3);
    expect(cancelled, isTrue);
    expect(transport.requests[0].$1, AgentChatWire.respond);
    expect(transport.requests[0].$2, <String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'requestId': 'req-1',
      'runtimeRequestId': 'rt-9',
      'response': <String, Object?>{
        'type': 'userInput',
        'answers': <String, Object?>{
          'scope': <String>['all', 'and tests'],
        },
      },
    });
    expect(transport.requests[1].$2, <String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'requestId': 'req-2',
      'provider': 'claudeAgent',
      'runtimeMode': 'auto-accept-edits',
    });
    expect(
      transport.requests[1].$3,
      isNotNull,
      reason: 'a provider switch waits for the new session',
    );
    expect(transport.requests[2].$2['queueId'], 'q-1');
  });

  test('a redirecting send needs the runtime to decline atomically', () async {
    final transport = _FakeTransport();
    final repository = RuntimeAgentChatRepository(transport);
    await expectLater(
      repository.send(
        const AgentChatSendInput(
          chatId: 'chat-1',
          workspaceId: 'ws-1',
          clientMessageId: 'msg-1',
          text: 'Redirect',
          declineRequestIds: <String>['request-1'],
        ),
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('send uses the client message id as its idempotency key', () async {
    final transport = _FakeTransport()
      ..responses[AgentChatWire.send] = <String, Object?>{
        'delivery': 'queued',
        'queueId': 'q-7',
      };
    final repository = RuntimeAgentChatRepository(transport);
    final result = await repository.send(
      const AgentChatSendInput(
        chatId: 'chat-1',
        workspaceId: 'ws-1',
        clientMessageId: 'msg-1',
        text: 'Run the tests',
        attachments: <AgentChatAttachment>[
          AgentChatAttachment(
            type: AgentChatAttachmentType.localImage,
            path: '/tmp/shot.png',
          ),
        ],
        interactionMode: AgentChatInteractionMode.plan,
      ),
    );
    expect(result.delivery, AgentChatSendDelivery.queued);
    expect(result.queueId, 'q-7');
    expect(transport.requests.single.$2, <String, Object?>{
      'requestId': 'msg-1',
      'clientMessageId': 'msg-1',
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'text': 'Run the tests',
      'attachments': <Object?>[
        <String, Object?>{'type': 'localImage', 'path': '/tmp/shot.png'},
      ],
      'interactionMode': 'plan',
      'delivery': 'auto',
    });
  });

  test('create and reopen return the chat, tab and snapshot', () async {
    final transport = _FakeTransport()
      ..responses[AgentChatWire.create] = <String, Object?>{
        'chatId': 'chat-1',
        'tabId': 'tab-1',
        'snapshot': _snapshotJson(),
      };
    final repository = RuntimeAgentChatRepository(transport);
    final result = await repository.create(
      const AgentChatCreateInput(
        requestId: 'req-1',
        workspaceId: 'ws-1',
        provider: 'codex',
        model: 'gpt-5',
      ),
    );
    expect(result.chatId, 'chat-1');
    expect(result.tabId, 'tab-1');
    expect(transport.requests.single.$2, <String, Object?>{
      'requestId': 'req-1',
      'workspaceId': 'ws-1',
      'provider': 'codex',
      'model': 'gpt-5',
    });
  });

  test('watch filters by chat and maps the connection lifecycle', () async {
    final transport = _FakeTransport();
    final repository = RuntimeAgentChatRepository(transport);
    final received = <AgentChatStreamEvent>[];
    final subscription = repository.watch('chat-1').listen(received.add);
    transport.controller
      ..add(
        const AgentChatTransportEvent(AgentChatWire.changedEvent, {
          'chatId': 'other',
          'cursor': 1,
        }),
      )
      ..add(
        const AgentChatTransportEvent(AgentChatWire.changedEvent, {
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 4,
          'delta': <String, Object?>{'title': 'Renamed'},
        }),
      )
      ..add(
        const AgentChatTransportEvent(
          AgentChatTransportEvents.disconnected,
          {},
        ),
      )
      ..add(
        const AgentChatTransportEvent(AgentChatTransportEvents.connected, {}),
      )
      // An unreadable change still moved the cursor, so it forces a resync.
      ..add(
        const AgentChatTransportEvent(AgentChatWire.changedEvent, {
          'chatId': 'chat-1',
          'cursor': 5,
          'delta': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'type': 'assistant_message'},
            ],
          },
        }),
      );
    await Future.pause(Duration.zero);
    await subscription.cancel();
    expect(received, hasLength(4));
    final change = (received[0] as AgentChatChangeReceived).change;
    expect(change.cursor, 4);
    expect(change.title, 'Renamed');
    expect(received[1], isA<AgentChatConnectionLost>());
    expect(received[2], isA<AgentChatResyncRequired>());
    expect(received[3], isA<AgentChatResyncRequired>());
  });

  test('list changes are scoped and reconnects refresh every list', () async {
    final transport = _FakeTransport();
    final repository = RuntimeAgentChatRepository(transport);
    final received = <AgentChatListChanged>[];
    final subscription = repository.watchList().listen(received.add);
    transport.controller
      ..add(
        const AgentChatTransportEvent(AgentChatWire.listChangedEvent, {
          'workspaceId': 'ws-2',
        }),
      )
      ..add(
        const AgentChatTransportEvent(AgentChatTransportEvents.connected, {}),
      );
    await Future.pause(Duration.zero);
    await subscription.cancel();
    expect(received.map((event) => event.workspaceId), <String?>['ws-2', null]);
  });

  test('error codes map to shared copy', () {
    expect(
      agentChatErrorMessage(
        const AgentChatRequestException(
          message: 'busy',
          code: AgentChatErrorCodes.turnActive,
        ),
      ),
      contains('Wait for the current turn'),
    );
    expect(
      agentChatErrorMessage(
        const AgentChatRequestException(message: 'Provider crashed.'),
      ),
      'Provider crashed.',
    );
    expect(
      agentChatErrorMessage(const AgentChatUpdateRequired()),
      contains('Update it'),
    );
    const nativeMessages = <String, String>{
      AgentChatErrorCodes.nativeOperationUncertain: 'Alera could not confirm how the rewind ended. Choose how to continue in the notice above the composer. Your draft is kept.',
      AgentChatErrorCodes.nativeOperationPending: 'A rewind is still being resolved. Send is paused and your draft is kept.',
      AgentChatErrorCodes.nativeOperationRevisionConflict: 'The chat changed while the rewind was being resolved. Review the latest state and choose again.',
    };
    for (final entry in nativeMessages.entries) {
      expect(
        agentChatErrorMessage(
          AgentChatRequestException(
            code: entry.key,
            message: 'Provider-specific details.',
          ),
        ),
        entry.value,
      );
    }
  });
}
