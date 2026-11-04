import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');

void main() {
  test('snapshots and deltas carry the title job and generated titles', () {
    final thread = AgentChatThread.fromSnapshot(
      AgentChatSnapshot.fromJson(<String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'cursor': 1,
        'title': 'Fix the login crash',
        'titleSource': 'derived',
      }),
    );
    expect(thread.titleGeneration, isNull);
    final generating = thread.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 2,
        'delta': <String, Object?>{
          'titleGeneration': <String, Object?>{
            'status': 'generating',
            'mode': 'regenerate',
            'jobId': 'title-1',
          },
        },
      }),
    );
    final pending = (generating as AgentChatApplied).thread;
    expect(pending.titleGeneration?.generating, isTrue);
    expect(pending.titleGeneration?.mode, 'regenerate');
    final done = pending.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 3,
        'delta': <String, Object?>{
          'title': 'Android Login Crash',
          'titleSource': 'generated',
          'titleGeneration': <String, Object?>{'status': 'idle'},
        },
      }),
    );
    final titled = (done as AgentChatApplied).thread;
    expect(titled.title, 'Android Login Crash');
    expect(titled.titleSource, AgentChatTitleSource.generated);
    expect(AgentChatTitleSource.generated.wire, 'generated');
    expect(titled.titleGeneration?.generating, isFalse);
    // A delta without the key leaves the job as it was; null clears it.
    final unchanged = titled.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 4,
        'delta': <String, Object?>{'title': 'Other'},
      }),
    );
    expect((unchanged as AgentChatApplied).thread.titleGeneration, isNotNull);
    final cleared = unchanged.thread.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'c',
        'cursor': 5,
        'delta': <String, Object?>{'titleGeneration': null},
      }),
    );
    expect((cleared as AgentChatApplied).thread.titleGeneration, isNull);
  });

  test('a failed job reports why', () {
    final failed = AgentChatTitleGeneration.fromJson(<String, Object?>{
      'status': 'failed',
      'errorMessage': 'AI Assist is disabled.',
    });
    expect(failed.failed, isTrue);
    expect(failed.errorMessage, 'AI Assist is disabled.');
  });

  test('regenerating a title needs the runtime capability', () async {
    await expectLater(
      _Legacy().regenerateTitle(_chat, requestId: 'r'),
      throwsUnsupportedError,
    );
    final transport = AgentChatContractTransport();
    addTearDown(transport.controller.close);
    final lifecycle = RuntimeAgentChatLifecycleRepository(transport);
    await expectLater(
      lifecycle.regenerateTitle(_chat, requestId: 'r'),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    transport.capabilities.add(AgentChatWire.titleGenerationCapability);
    await lifecycle.regenerateTitle(
      _chat,
      requestId: 'r2',
      replaceUserTitle: true,
    );
    final (verb, payload) = transport.requests.single;
    expect(verb, 'agentChat.regenerateTitle');
    expect(payload['chatId'], 'c');
    expect(payload['replaceUserTitle'], isTrue);
    expect(
      AgentChatWire.titleGenerationCapability,
      'agentChatTitleGenerationV1',
    );
    expect(
      AgentChatOrchestrationWire.updateTitle,
      'chatOrchestration.updateTitle',
    );
  });
}

final class _Legacy extends AgentChatLifecycleRepository {}
