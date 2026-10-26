import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime.utc(2026, 10, 25, 12);

AgentChatRequest _approval(
  String id, {
  bool feedback = false,
  int minutesAgo = 0,
}) => AgentChatRequest(
  id: id,
  kind: .commandExecutionApproval,
  createdAt: _now.subtract(Duration(minutes: minutesAgo)),
  decisions: const <AgentChatApprovalDecision>[.accept, .decline, .cancel],
  supportsFeedback: feedback,
);

final class _Port {
  _Port(this.pending, {this.atomic = false});

  List<AgentChatRequest> pending;
  bool atomic;
  bool changed = false;
  bool current = true;
  Set<String> responding = <String>{};
  Object? refusal;
  final List<(String, AgentChatJson)> responses = <(String, AgentChatJson)>[];
  final List<List<String>> declining = <List<String>>[];
  int sends = 0;

  /// Runs after each answer, as a provider event would.
  void Function()? afterRespond;

  AgentChatApprovalSendPort get port => AgentChatApprovalSendPort(
    draftChanged: () => changed,
    current: () => current,
    pendingRequests: () => pending,
    respondingRequestIds: () => responding,
    respond: (request, response) async {
      responses.add((request.id, response.toJson()));
      afterRespond?.call();
      return true;
    },
    atomic: () async => atomic,
    sendDeclining: (ids) async {
      if (refusal case final Object error) throw error;
      declining.add(ids);
    },
    send: () async {
      sends += 1;
      return true;
    },
  );
}

Future<AgentChatApprovalSendOutcome> _send(
  _Port port, {
  String text = '  Use the release build.  ',
  bool attachments = false,
}) => agentChatSendOverApprovals(
  agentChatApprovalSend(port.pending)!,
  text: text,
  hasAttachments: attachments,
  port: port.port,
);

void main() {
  test('the shown approval decides between feedback and redirect', () {
    final question = AgentChatRequest(
      id: 'question',
      kind: .toolUserInput,
      createdAt: _now.subtract(const Duration(minutes: 9)),
    );
    expect(agentChatApprovalSend(<AgentChatRequest>[question]), isNull);
    final feedback = agentChatApprovalSend(<AgentChatRequest>[
      question,
      _approval('later', minutesAgo: 1),
      _approval('shown', feedback: true, minutesAgo: 2),
    ])!;
    expect(feedback.feedbackTarget?.id, 'shown');
    expect(feedback.approvalIds, <String>['shown', 'later']);
    expect(feedback.hint, agentChatApprovalFeedbackHint);
    expect(feedback.sendLabel, agentChatApprovalFeedbackSendLabel);
    final redirect = agentChatApprovalSend(<AgentChatRequest>[
      _approval('shown', minutesAgo: 2),
      _approval('later', feedback: true, minutesAgo: 1),
    ])!;
    expect(redirect.feedbackTarget, isNull);
    expect(redirect.hint, agentChatApprovalRedirectHint);
    expect(redirect.sendLabel, agentChatApprovalRedirectSendLabel);
  });

  test('redirect notices mirror why the message stayed', () {
    String? notice({
      bool draftChanged = false,
      bool declined = true,
      bool responding = false,
      bool arrived = false,
    }) => agentChatApprovalRedirectNotice(
      draftChanged: draftChanged,
      declined: declined,
      approvalResponding: responding,
      approvalArrived: arrived,
    );
    expect(
      notice(draftChanged: true),
      "Approval declined. Your message changed, so it wasn't sent.",
    );
    expect(
      notice(draftChanged: true, declined: false),
      "Your message changed, so it wasn't sent.",
    );
    expect(
      notice(declined: false, responding: true),
      contains('already being answered'),
    );
    expect(notice(arrived: true), contains('Another approval arrived'));
    expect(notice(declined: false), isNull);
    expect(notice(), isNull);
  });

  test('feedback declines the shown approval with the trimmed text', () async {
    final port = _Port(<AgentChatRequest>[_approval('a', feedback: true)]);
    final outcome = await _send(port);
    expect(outcome.sent, isTrue);
    final (id, response) = port.responses.single;
    expect(id, 'a');
    expect(response, <String, Object?>{
      'type': 'approval',
      'decision': 'decline',
      'feedback': 'Use the release build.',
    });
    expect(port.sends + port.declining.length, 0);
  });

  test('feedback refuses attachments and a changed draft', () async {
    final port = _Port(<AgentChatRequest>[_approval('a', feedback: true)]);
    final refused = await _send(port, attachments: true);
    expect(refused.error, agentChatApprovalFeedbackAttachmentsError);
    port.changed = true;
    final changed = await _send(port);
    expect(changed.sent, isFalse);
    expect(changed.notice, isNull);
    expect(port.responses, isEmpty);
  });

  test('an atomic redirect names every approval the sender saw', () async {
    final port = _Port(<AgentChatRequest>[
      _approval('a', minutesAgo: 2),
      _approval('b', minutesAgo: 1),
    ], atomic: true);
    expect((await _send(port)).sent, isTrue);
    expect(port.declining.single, <String>['a', 'b']);
    expect(port.responses, isEmpty);

    port.refusal = const AgentChatRequestException(
      message: "Another approval arrived, so your message wasn't sent.",
      code: AgentChatErrorCodes.approvalsChanged,
    );
    final refused = await _send(port);
    expect(refused.sent, isFalse);
    expect(refused.notice, contains('Another approval arrived'));
  });

  test(
    'a redirect stops before declining for a draft or approval in flux',
    () async {
      final port = _Port(<AgentChatRequest>[_approval('a')], atomic: true)
        ..responding = <String>{'a'};
      expect((await _send(port)).notice, contains('already being answered'));
      port
        ..responding = <String>{}
        ..changed = true;
      expect(
        (await _send(port)).notice,
        "Your message changed, so it wasn't sent.",
      );
      expect(port.declining, isEmpty);
    },
  );

  test(
    'without the capability the redirect declines, rechecks, then sends',
    () async {
      final port = _Port(<AgentChatRequest>[
        _approval('a', minutesAgo: 2),
        _approval('b', minutesAgo: 1),
      ]);
      expect((await _send(port)).sent, isTrue);
      expect(
        <String>[for (final (id, _) in port.responses) id],
        <String>['a', 'b'],
      );
      expect(port.responses.first.$2['decision'], 'decline');
      expect(port.sends, 1);

      final arriving = _Port(<AgentChatRequest>[_approval('a')]);
      arriving.afterRespond = () =>
          arriving.pending = <AgentChatRequest>[_approval('c')];
      final arrived = await _send(arriving);
      expect(arrived.notice, contains('Another approval arrived'));
      expect(arriving.sends, 0);

      final editing = _Port(<AgentChatRequest>[_approval('a')]);
      editing.afterRespond = () => editing.changed = true;
      expect(
        (await _send(editing)).notice,
        "Approval declined. Your message changed, so it wasn't sent.",
      );
      expect(editing.sends, 0);

      final leaving = _Port(<AgentChatRequest>[_approval('a')]);
      leaving.afterRespond = () => leaving.current = false;
      final left = await _send(leaving);
      expect(left.sent, isFalse);
      expect(left.notice, isNull);
      expect(leaving.sends, 0);
    },
  );

  test('send input carries the approvals to decline', () {
    const input = AgentChatSendInput(
      chatId: 'chat',
      workspaceId: 'ws',
      clientMessageId: 'msg',
      text: 'Redirect',
      declineRequestIds: <String>['a', 'b'],
    );
    expect(input.toJson()['declineRequests'], <String, Object?>{
      'requestIds': <String>['a', 'b'],
    });
    expect(
      const AgentChatSendInput(
        chatId: 'chat',
        workspaceId: 'ws',
        clientMessageId: 'msg',
        text: 'Plain',
      ).toJson().containsKey('declineRequests'),
      isFalse,
    );
  });
}
