import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');

void main() {
  late AgentChatContractTransport transport;
  late RuntimeAgentChatRepository repository;
  setUp(() {
    transport = AgentChatContractTransport();
    repository = RuntimeAgentChatRepository(transport);
  });
  tearDown(() => transport.controller.close());

  test('unselected draft and effort fields are capability guarded', () async {
    await expectLater(
      repository.create(
        const AgentChatCreateInput(requestId: 'r', workspaceId: 'w'),
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    await expectLater(
      repository.send(
        const AgentChatSendInput(
          chatId: 'c',
          workspaceId: 'w',
          clientMessageId: 'm',
          text: 'hi',
          reasoningEffort: 'high',
        ),
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    await expectLater(
      repository.configure(
        _chat,
        requestId: 'r',
        configuration: const AgentChatConfiguration(resetReasoningEffort: true),
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
    transport.capabilities.addAll(<String>{
      AgentChatWire.unselectedDraftCapability,
      AgentChatWire.effortCapability,
    });
    transport.responses[AgentChatWire.create] = <String, Object?>{
      'snapshot': agentChatContractSnapshot(),
    };
    await repository.create(
      const AgentChatCreateInput(requestId: 'r', workspaceId: 'w'),
    );
    expect(transport.requests.single.$2.containsKey('provider'), isFalse);
    await repository.send(
      const AgentChatSendInput(
        chatId: 'c',
        workspaceId: 'w',
        clientMessageId: 'm',
        text: 'hi',
        reasoningEffort: 'high',
      ),
    );
    expect(transport.requests.last.$2['reasoningEffort'], 'high');
  });

  test(
    'atomic queue steer uses one verb with the queue and live turn ids',
    () async {
      transport.capabilities.add(AgentChatWire.queueSteerCapability);
      transport.responses[AgentChatWire.queueSteer] = <String, Object?>{
        'delivery': 'steered',
        'queueId': 'q',
        'itemId': 'i',
        'turnId': 't',
      };
      final result = await repository.lifecycle.queueSteer(
        const AgentChatQueueSteerInput(
          chatId: 'c',
          workspaceId: 'w',
          requestId: 'r',
          queueId: 'q',
          turnId: 't',
        ),
      );
      expect(result.delivery, AgentChatSendDelivery.steered);
      expect(result.queueId, 'q');
      expect(transport.requests.single.$1, AgentChatWire.queueSteer);
      expect(transport.requests.single.$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'requestId': 'r',
        'queueId': 'q',
        'turnId': 't',
      });
    },
  );

  test(
    'queue edit reads the runtime answer and reorder sends the position',
    () async {
      transport.capabilities.addAll(<String>[
        AgentChatWire.queueEditCapability,
        AgentChatWire.queueReorderCapability,
      ]);
      transport.responses[AgentChatWire.queueEdit] = <String, Object?>{
        'updated': true,
        'queueId': 'q',
      };
      transport.responses[AgentChatWire.queueReorder] = <String, Object?>{
        'reordered': true,
        'queueId': 'q',
        'index': 0,
      };
      expect(
        await repository.lifecycle.queueEdit(
          _chat,
          requestId: 'edit',
          queueId: 'q',
          text: 'new',
        ),
        isTrue,
      );
      expect(
        await repository.lifecycle.queueReorder(
          _chat,
          requestId: 'move',
          queueId: 'q',
          index: 0,
        ),
        isTrue,
      );
      expect(transport.requests.last.$1, AgentChatWire.queueReorder);
      expect(transport.requests.last.$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'requestId': 'move',
        'queueId': 'q',
        'index': 0,
      });
    },
  );

  test('queue reorder fails closed without its capability', () async {
    await expectLater(
      repository.lifecycle.queueReorder(
        _chat,
        requestId: 'move',
        queueId: 'q',
        index: 1,
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'every history action fails closed without its own capability',
    () async {
      await expectLater(
        repository.lifecycle.fork(_chat, requestId: 'fork', turnId: 't'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.rewind(_chat, requestId: 'rewind', turnId: 't'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.delete(_chat, requestId: 'delete'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.approvalHistory(_chat),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.turnDiff(_chat, turnId: 't'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.skills(_chat),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test('skills read the agent list for the chat and can refresh it', () async {
    transport.capabilities.add(AgentChatWire.skillsCapability);
    transport.responses[AgentChatWire.skills] = <String, Object?>{
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'status': 'ready',
      'source': 'discovery',
      'skills': <Object?>[
        <String, Object?>{
          'name': 'review',
          'path': '/s/SKILL.md',
          'enabled': true,
        },
      ],
    };
    final list = await repository.lifecycle.skills(_chat);
    expect(list.status, AgentChatSkillsStatus.ready);
    expect(list.skills.single.name, 'review');
    expect(transport.requests.single.$1, AgentChatWire.skills);
    expect(transport.requests.single.$2['chatId'], _chat.chatId);
    expect(transport.requests.single.$2.containsKey('refresh'), isFalse);
    await repository.lifecycle.skills(_chat, refresh: true);
    expect(transport.requests.last.$2['refresh'], isTrue);
  });

  test('rewind returns the prompt and attachments without promising filesystem reversal', () async {
    transport.capabilities.add(AgentChatWire.rewindCapability);
    transport.responses[AgentChatWire.rewind] = <String, Object?>{
      'snapshot': agentChatContractSnapshot(),
      'prompt': 'Try again',
      'filesystemChangesReverted': false,
      'attachments': <Object?>[
        <String, Object?>{'type': 'file', 'path': '/tmp/input.txt'},
      ],
    };
    final result = await repository.lifecycle.rewind(
      _chat,
      requestId: 'r',
      turnId: 't',
    );
    expect(result.prompt, 'Try again');
    expect(result.attachments.single.path, '/tmp/input.txt');
    expect(result.filesystemChangesReverted, isFalse);
    expect(transport.requests.single.$2['turnId'], 't');
  });

  test('close distinguishes a discarded draft from an archive on new and old hosts', () async {
    expect(
      (await repository.lifecycle.close(_chat, requestId: 'old')).archived,
      isTrue,
    );
    transport.responses[AgentChatWire.close] = <String, Object?>{
      'archived': false,
      'discarded': true,
    };
    final result = await repository.lifecycle.close(_chat, requestId: 'draft');
    expect(result.discarded, isTrue);
    expect(result.archived, isFalse);
  });

  test(
    'read cursor is host-scoped and preserves the returned monotonic cursor',
    () async {
      transport.capabilities.add(AgentChatWire.readCursorCapability);
      transport.responses[AgentChatWire.markRead] = <String, Object?>{
        'readCursor': 9,
      };
      expect(
        await repository.lifecycle.markRead(_chat, requestId: 'r', cursor: 3),
        9,
      );
      expect(transport.requests.single.$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'requestId': 'r',
        'cursor': 3,
      });
      await expectLater(
        repository.lifecycle.markRead(_chat, requestId: 'bad', cursor: -1),
        throwsFormatException,
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'removed events are chat-scoped and invalidate the workspace list',
    () async {
      final chatEvents = <AgentChatStreamEvent>[];
      final listEvents = <AgentChatListChanged>[];
      final chatSubscription = repository.watch('c').listen(chatEvents.add);
      final listSubscription = repository.watchList().listen(listEvents.add);
      transport.controller
        ..add(
          const AgentChatTransportEvent(
            AgentChatWire.deletedEvent,
            <String, Object?>{
              'chatId': 'other',
              'workspaceId': 'elsewhere',
              'discarded': false,
            },
          ),
        )
        ..add(
          const AgentChatTransportEvent(
            AgentChatWire.deletedEvent,
            <String, Object?>{
              'chatId': 'c',
              'workspaceId': 'w',
              'discarded': true,
            },
          ),
        );
      await Future.pause(Duration.zero);
      await chatSubscription.cancel();
      await listSubscription.cancel();
      expect((chatEvents.single as AgentChatRemoved).discarded, isTrue);
      expect(listEvents.map((event) => event.workspaceId), <String>[
        'elsewhere',
        'w',
      ]);
    },
  );

  test(
    'title source deltas preserve user renames through the shared reducer',
    () {
      final thread = AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          ...agentChatContractSnapshot(),
          'title': 'Original',
          'titleSource': 'derived',
        }),
      );
      final result = thread.apply(
        AgentChatChange.fromJson(<String, Object?>{
          'chatId': 'c',
          'cursor': 4,
          'delta': <String, Object?>{
            'title': 'Personal',
            'titleSource': 'user',
          },
        }),
      ) as AgentChatApplied;
      expect(result.thread.snapshot.titleSource, AgentChatTitleSource.user);
      expect(
        result.thread.snapshot.copyWith(cursor: 5).titleSource,
        AgentChatTitleSource.user,
      );
      expect(result.thread.snapshot.neverSent, isTrue);
      expect(result.thread.snapshot.hasSelection, isTrue);
    },
  );

  test(
    'old repository fakes can inherit unsupported extension services',
    () async {
      const lifecycle = UnsupportedAgentChatLifecycleRepository();
      expect(await lifecycle.supports(AgentChatWire.forkCapability), isFalse);
      await expectLater(
        lifecycle.close(_chat, requestId: 'r'),
        throwsUnsupportedError,
      );
    },
  );
}
