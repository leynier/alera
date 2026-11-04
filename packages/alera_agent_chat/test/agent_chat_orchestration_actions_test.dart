import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

final class _Transport implements AgentChatTransport {
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];

  @override
  Stream<AgentChatTransportEvent> get events =>
      const Stream<AgentChatTransportEvent>.empty();

  @override
  Future<bool> supportsCapability(String capability) async => true;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload));
    return <String, Object?>{
      'task': <String, Object?>{'taskId': 'task-1', 'status': 'completed'},
      'chatId': 'chat-1',
      'taskId': 'task-2',
    };
  }
}

AgentChatTask _task({
  String? parentChatId,
  AgentChatTaskStatus status = AgentChatTaskStatus.completed,
  AgentChatTaskDelivery delivery = AgentChatTaskDelivery.pending,
}) => AgentChatTask(
  id: 'task-1',
  status: status,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  parentChatId: parentChatId,
  delivery: delivery,
);

void main() {
  test('only a settled, unread result a person owns is acknowledged', () async {
    final transport = _Transport();
    var next = 0;
    final actions = AgentChatTaskActions(
      RuntimeAgentChatOrchestrationRepository(transport),
      () => 'id-${next++}',
    );
    await actions.acknowledge(_task(parentChatId: 'chat-parent'));
    await actions.acknowledge(_task(status: AgentChatTaskStatus.running));
    await actions.acknowledge(
      _task(delivery: AgentChatTaskDelivery.acknowledged),
    );
    expect(transport.requests, isEmpty);
    await actions.acknowledge(_task());
    expect(transport.requests.single.$2, <String, Object?>{
      'taskId': 'task-1',
      'acknowledge': true,
    });
  });

  test(
    'a follow-up expects a reply and every press is a new request',
    () async {
      final transport = _Transport();
      var next = 0;
      final actions = AgentChatTaskActions(
        RuntimeAgentChatOrchestrationRepository(transport),
        () => 'id-${next++}',
      );
      final sent = await actions.followUp('chat-1', '  Check the tests  ');
      expect(sent.taskId, 'task-2');
      await actions.cancel('task-1');
      await actions.cancel('task-1');
      expect(transport.requests[0].$2, <String, Object?>{
        'requestId': 'id-0',
        'chatId': 'chat-1',
        'message': 'Check the tests',
        'delivery': 'auto',
        'expectReply': true,
      });
      expect(
        transport.requests.skip(1).map((request) => request.$2['requestId']),
        <String>['id-1', 'id-2'],
      );
    },
  );
}
