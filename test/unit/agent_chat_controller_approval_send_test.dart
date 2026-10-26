import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final class _Lifecycle extends AgentChatLifecycleRepository {
  bool redirects = false;

  @override
  Future<bool> supports(String capability) async =>
      redirects && capability == AgentChatWire.approvalRedirectCapability;
}

Map<String, Object?> _approval(String id, {bool feedback = false}) =>
    <String, Object?>{
      'requestId': id,
      'kind': 'command_execution_approval',
      'createdAt': '2026-10-12T10:00:00Z',
      'decisions': <Object?>['accept', 'decline', 'cancel'],
      'supportsFeedback': feedback,
    };

void main() {
  late FakeAgentChatRepository repository;
  late _Lifecycle lifecycle;
  late ProviderContainer container;
  late int nextId;

  setUp(() {
    repository = FakeAgentChatRepository();
    lifecycle = _Lifecycle();
    nextId = 0;
    container = ProviderContainer(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  final provider = agentChatControllerProvider('chat-1', 'ws-1');

  Future<AgentChatApprovalSend> open(
    List<Map<String, Object?>> requests,
  ) async {
    repository.snapshots.add(
      () => agentChatSnapshotFixture(
        status: 'waiting',
        activeTurnId: 't1',
        requests: requests,
      ),
    );
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return agentChatApprovalSend(
      container.read(provider).projection!.requests,
    )!;
  }

  Future<AgentChatApprovalSendOutcome> sendOver(
    AgentChatApprovalSend plan, {
    List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
  }) => container
      .read(provider.notifier)
      .sendOverApprovals(
        plan,
        ' Use the release build. ',
        attachments: attachments,
        draftChanged: () => false,
      );

  List<Object?> calls(String name) => <Object?>[
    for (final (call, argument) in repository.calls)
      if (call == name) argument,
  ];

  test('feedback declines the shown approval and queues nothing', () async {
    final plan = await open(<Map<String, Object?>>[
      _approval('r1', feedback: true),
    ]);
    final outcome = await sendOver(plan);
    expect(outcome.sent, isTrue);
    final (id, response) =
        calls('respond').single! as (String, AgentChatResponse);
    expect(id, 'r1');
    expect(response.toJson(), <String, Object?>{
      'type': 'approval',
      'decision': 'decline',
      'feedback': 'Use the release build.',
    });
    expect(calls('send'), isEmpty);
    expect(container.read(provider).outgoing, isEmpty);
  });

  test('feedback with attachments shows an inline error', () async {
    final plan = await open(<Map<String, Object?>>[
      _approval('r1', feedback: true),
    ]);
    final outcome = await sendOver(
      plan,
      attachments: const <AgentChatAttachment>[
        AgentChatAttachment(type: AgentChatAttachmentType.file, path: '/a'),
      ],
    );
    expect(outcome.sent, isFalse);
    expect(
      container.read(provider).actionError,
      agentChatApprovalFeedbackAttachmentsError,
    );
    expect(calls('respond'), isEmpty);
  });

  test('a redirect declines and sends in one runtime request', () async {
    lifecycle.redirects = true;
    final plan = await open(<Map<String, Object?>>[_approval('r1')]);
    expect((await sendOver(plan)).sent, isTrue);
    final input = calls('send').single! as AgentChatSendInput;
    expect(input.text, 'Use the release build.');
    expect(input.declineRequestIds, <String>['r1']);
    expect(calls('respond'), isEmpty);
    expect(
      container.read(provider).outgoing.single.status,
      AgentChatOutgoingStatus.accepted,
    );
  });

  test('a redirect the runtime refuses keeps the draft and explains', () async {
    lifecycle.redirects = true;
    repository.sendError = const AgentChatRequestException(
      message: "Another approval arrived, so your message wasn't sent.",
      code: AgentChatErrorCodes.approvalsChanged,
    );
    final plan = await open(<Map<String, Object?>>[_approval('r1')]);
    final outcome = await sendOver(plan);
    expect(outcome.sent, isFalse);
    expect(outcome.notice, contains('Another approval arrived'));
    expect(container.read(provider).outgoing, isEmpty);
    expect(container.read(provider).actionError, isNull);
  });

  test('an older runtime gets the decline followed by a plain send', () async {
    final plan = await open(<Map<String, Object?>>[_approval('r1')]);
    expect((await sendOver(plan)).sent, isTrue);
    await pumpEventQueue();
    final (id, response) =
        calls('respond').single! as (String, AgentChatResponse);
    expect(id, 'r1');
    expect(response.toJson()['decision'], 'decline');
    final input = calls('send').single! as AgentChatSendInput;
    expect(input.declineRequestIds, isEmpty);
    expect(input.text, 'Use the release build.');
  });
}
