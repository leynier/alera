import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');
const _compact = AgentChatProviderCommand(name: 'compact');
const _feedback = AgentChatProviderCommand(
  name: 'feedback',
  description: 'Send this thread and Codex logs to OpenAI',
  inputHint: 'Describe the issue (optional)',
);

AgentChatFeedbackSubmission _submission() => AgentChatFeedbackSubmission(
  id: 'fb-1',
  command: '/feedback it broke',
  createdAt: DateTime.utc(2026, 10, 26),
);

void main() {
  group('parseAgentChatFeedbackCommand', () {
    test('reads the command alone or with a reason, as T3 Code does', () {
      expect(
        parseAgentChatFeedbackCommand('/feedback'),
        const AgentChatFeedbackCommand(),
      );
      expect(
        parseAgentChatFeedbackCommand('  /Feedback   \n'),
        const AgentChatFeedbackCommand(),
      );
      expect(
        parseAgentChatFeedbackCommand('/feedback  The diff\nwas empty  '),
        const AgentChatFeedbackCommand(reason: 'The diff\nwas empty'),
      );
      expect(
        parseAgentChatFeedbackCommand('/FEEDBACK\twrong file'),
        const AgentChatFeedbackCommand(reason: 'wrong file'),
      );
    });

    test('leaves other text a message', () {
      for (final text in <String>[
        '/feedbacks',
        '/feedback-now',
        'please /feedback',
        'feedback',
        '',
      ]) {
        expect(parseAgentChatFeedbackCommand(text), isNull, reason: text);
      }
    });
  });

  test('the composer runs /feedback only with the verb and the command', () {
    expect(
      agentChatFeedbackAvailable(
        supported: true,
        commands: const <AgentChatProviderCommand>[_compact, _feedback],
      ),
      isTrue,
    );
    expect(
      agentChatFeedbackAvailable(
        supported: false,
        commands: const <AgentChatProviderCommand>[_feedback],
      ),
      isFalse,
    );
    expect(
      agentChatFeedbackAvailable(
        supported: true,
        commands: const <AgentChatProviderCommand>[_compact],
      ),
      isFalse,
    );
  });

  test('the menu hides /feedback without the verb or a conversation', () {
    const commands = <AgentChatProviderCommand>[_compact, _feedback];
    expect(
      agentChatMenuProviderCommands(
        commands,
        feedbackSupported: true,
        hasConversation: true,
      ),
      commands,
    );
    for (final (supported, conversation) in <(bool, bool)>[
      (false, true),
      (true, false),
    ]) {
      expect(
        agentChatMenuProviderCommands(
          commands,
          feedbackSupported: supported,
          hasConversation: conversation,
        ),
        const <AgentChatProviderCommand>[_compact],
      );
    }
  });

  test('the consent copy names what is uploaded and repeats the reason', () {
    final plain = agentChatFeedbackConsentMessage(
      const AgentChatFeedbackCommand(),
    );
    expect(plain, contains('conversation thread'));
    expect(plain, contains('Codex logs'));
    expect(plain, contains('OpenAI'));
    expect(
      agentChatFeedbackConsentMessage(
        const AgentChatFeedbackCommand(reason: 'wrong file'),
      ),
      endsWith('"wrong file"'),
    );
  });

  test('notices follow T3 Code for each status', () {
    final uploading = _submission();
    expect(
      agentChatFeedbackNotice(uploading).title,
      'Sending feedback to OpenAI...',
    );
    final sent = agentChatFeedbackNotice(uploading.sent('thread-9'));
    expect(sent.title, 'Feedback sent to OpenAI');
    expect(sent.detail, 'Thread ID: thread-9');
    final failed = agentChatFeedbackNotice(uploading.failed('offline'));
    expect(failed.title, 'Could not send feedback to OpenAI');
    expect(failed.detail, 'offline');
  });

  test('upsert replaces by id and appends new submissions', () {
    final first = _submission();
    final second = AgentChatFeedbackSubmission(
      id: 'fb-2',
      command: '/feedback',
      createdAt: DateTime.utc(2026, 10, 27),
    );
    var list = agentChatFeedbackUpsert(const [], first);
    list = agentChatFeedbackUpsert(list, second);
    list = agentChatFeedbackUpsert(list, first.sent('x'));
    expect(list, <AgentChatFeedbackSubmission>[first.sent('x'), second]);
  });

  group('submitAgentChatFeedback', () {
    late AgentChatContractTransport transport;
    late RuntimeAgentChatLifecycleRepository lifecycle;
    setUp(() {
      transport = AgentChatContractTransport();
      lifecycle = RuntimeAgentChatLifecycleRepository(transport);
    });
    tearDown(() => transport.controller.close());

    test('reports uploading, then the feedback id', () async {
      transport.capabilities.add(AgentChatWire.feedbackCapability);
      transport.responses[AgentChatWire.feedback] = <String, Object?>{
        'feedbackId': 'thread-9',
      };
      final updates = <AgentChatFeedbackSubmission>[];
      final result = await submitAgentChatFeedback(
        lifecycle: lifecycle,
        chat: _chat,
        submission: _submission(),
        command: const AgentChatFeedbackCommand(reason: 'it broke'),
        onUpdate: updates.add,
      );
      expect(updates.map((update) => update.status), <AgentChatFeedbackStatus>[
        .uploading,
        .sent,
      ]);
      expect(result.feedbackId, 'thread-9');
      expect(transport.requests.single.$1, AgentChatWire.feedback);
      expect(transport.requests.single.$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'requestId': 'fb-1',
        'reason': 'it broke',
      });
    });

    test('a runtime without the verb fails without a request', () async {
      final result = await submitAgentChatFeedback(
        lifecycle: lifecycle,
        chat: _chat,
        submission: _submission(),
        command: const AgentChatFeedbackCommand(),
        onUpdate: (_) {},
      );
      expect(result.status, AgentChatFeedbackStatus.failed);
      expect(result.errorMessage, contains(AgentChatWire.feedbackCapability));
      expect(transport.requests, isEmpty);
    });

    test('a refused upload keeps the runtime message', () async {
      final failing = _FailingLifecycle(
        const AgentChatRequestException(
          message: 'Fixture feedback upload refused.',
          code: AgentChatErrorCodes.feedbackFailed,
        ),
      );
      final result = await submitAgentChatFeedback(
        lifecycle: failing,
        chat: _chat,
        submission: _submission(),
        command: const AgentChatFeedbackCommand(),
        onUpdate: (_) {},
      );
      expect(result.status, AgentChatFeedbackStatus.failed);
      expect(result.errorMessage, 'Fixture feedback upload refused.');
    });
  });

  test('the repository omits a blank reason and needs a feedback id', () async {
    final transport = AgentChatContractTransport(
      capabilities: <String>{
        AgentChatWire.capability,
        AgentChatWire.feedbackCapability,
      },
    );
    addTearDown(transport.controller.close);
    final lifecycle = RuntimeAgentChatLifecycleRepository(transport);
    await expectLater(
      lifecycle.feedback(_chat, requestId: 'r', reason: '   '),
      throwsA(isA<FormatException>()),
    );
    expect(transport.requests.single.$2.containsKey('reason'), isFalse);
  });
}

final class _FailingLifecycle extends AgentChatLifecycleRepository {
  const _FailingLifecycle(this.error);

  final Object error;

  @override
  Future<String> feedback(
    AgentChatRef chat, {
    required String requestId,
    String? reason,
  }) => Future<String>.error(error);
}
