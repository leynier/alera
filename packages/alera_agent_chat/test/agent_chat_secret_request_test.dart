import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');

void main() {
  test('a secret card parses as a masked secret request', () {
    final request = AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'request-1',
      'kind': 'secret_input',
      'createdAt': '2026-11-02T00:00:00.000Z',
      'title': 'Deploy token',
      'detail': 'To deploy.',
      'masked': true,
      'answerBy': 'host',
      'questions': <Object?>[
        <String, Object?>{
          'id': 'value',
          'header': 'Deploy token',
          'question': 'To deploy.',
          'masked': true,
          'placeholder': 'ghp_...',
        },
      ],
    });
    expect(request.kind, AgentChatRequestKind.secretInput);
    expect(request.isSecret, isTrue);
    expect(request.isQuestion, isFalse);
    expect(request.isApproval, isFalse);
    expect(request.masked, isTrue);
    expect(request.placeholder, 'ghp_...');
    expect(agentChatRequestKindTitle(request.kind), 'Secret Requested');
  });

  test('providing a secret needs the runtime capability', () async {
    await expectLater(
      _Legacy().provideSecret(_chat, runtimeRequestId: 'r', value: 'x'),
      throwsUnsupportedError,
    );
    final transport = AgentChatContractTransport();
    addTearDown(transport.controller.close);
    final lifecycle = RuntimeAgentChatLifecycleRepository(transport);
    await expectLater(
      lifecycle.provideSecret(_chat, runtimeRequestId: 'r'),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    transport.capabilities.add(AgentChatWire.secretRequestsCapability);
    await lifecycle.provideSecret(_chat, runtimeRequestId: 'r1');
    final (verb, payload) = transport.requests.single;
    expect(verb, 'agentChat.secret.provide');
    expect(payload['runtimeRequestId'], 'r1');
    expect(payload['action'], 'decline');
    expect(payload.containsKey('value'), isFalse);
    expect(AgentChatWire.secretRequestsCapability, 'agentChatSecretRequestsV1');
  });

  test('a secret response goes to the provide verb, not respond', () async {
    final transport = AgentChatContractTransport()
      ..capabilities.add(AgentChatWire.secretRequestsCapability);
    addTearDown(transport.controller.close);
    final repository = RuntimeAgentChatRepository(transport);
    const response = AgentChatSecretResponse('synthetic-test-value');
    await repository.respond(
      _chat,
      requestId: 'r',
      runtimeRequestId: 'request-1',
      response: response,
    );
    final (verb, payload) = transport.requests.single;
    expect(verb, 'agentChat.secret.provide');
    expect(payload['action'], 'save');
    expect(response.toJson().containsKey('value'), isFalse);
    expect(response.toString().contains('synthetic'), isFalse);
  });
  test('a pull request watch notice is an automated origin', () {
    final origin = AgentChatItemOrigin.fromJson(<String, Object?>{
      'kind': 'pullRequestWatch',
    });
    expect(origin.kind, AgentChatItemOriginKind.pullRequestWatch);
    expect(origin.automated, isTrue);
    expect(agentChatOriginHeading(origin), 'Pull request update');
  });
}

final class _Legacy extends AgentChatLifecycleRepository {}
