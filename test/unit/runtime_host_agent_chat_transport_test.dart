import 'dart:async';

import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeRuntimeClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final StreamController<RuntimeHostEvent> controller =
      StreamController<RuntimeHostEvent>.broadcast();
  Object? error;
  Object? response = const <String, Object?>{'ok': true};
  Set<String> capabilities = <String>{'agentChatV1'};
  final List<(String, Map<String, Object?>, Duration?)> requests =
      <(String, Map<String, Object?>, Duration?)>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => controller.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add((type, payload, timeout));
    final error = this.error;
    if (error != null) throw error;
    return response;
  }

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);
}

void main() {
  test('maps host failures onto package exceptions', () async {
    final client = _FakeRuntimeClient();
    final transport = RuntimeHostAgentChatTransport(client);
    client.error = const TerminalHostConflictException(
      code: 'turnActive',
      message: 'A turn is running.',
      details: <String, Object?>{'turnId': 't1'},
    );
    await expectLater(
      transport.request('agentChat.configure', const <String, Object?>{}),
      throwsA(
        isA<AgentChatRequestException>()
            .having((error) => error.code, 'code', 'turnActive')
            .having((error) => error.details['turnId'], 'details', 't1'),
      ),
    );
    client.error = const TerminalHostConnectionClosedException();
    await expectLater(
      transport.request('agentChat.send', const <String, Object?>{}),
      throwsA(isA<AgentChatConnectionException>()),
    );
    client.error = const TerminalHostRequestTimeoutException(
      'agentChat.send',
      Duration(seconds: 30),
    );
    await expectLater(
      transport.request('agentChat.send', const <String, Object?>{}),
      throwsA(isA<AgentChatConnectionException>()),
    );
    client.error = StateError('Unknown request.');
    await expectLater(
      transport.request('agentChat.send', const <String, Object?>{}),
      throwsA(
        isA<AgentChatRequestException>().having(
          (error) => error.message,
          'message',
          'Unknown request.',
        ),
      ),
    );
  });

  test('passes a default timeout and returns the response object', () async {
    final client = _FakeRuntimeClient();
    final transport = RuntimeHostAgentChatTransport(client);
    final response = await transport.request(
      'agentChat.snapshot',
      const <String, Object?>{'chatId': 'c'},
    );
    expect(response, <String, Object?>{'ok': true});
    expect(client.requests.single.$3, isNotNull);
    expect(await transport.supportsCapability('agentChatV1'), isTrue);
    expect(await transport.supportsCapability('other'), isFalse);
  });

  test('renames connection events to the package lifecycle', () async {
    final client = _FakeRuntimeClient();
    final transport = RuntimeHostAgentChatTransport(client);
    final names = <String>[];
    final subscription = transport.events.listen(
      (event) => names.add(event.name),
    );
    client.controller
      ..add(const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}))
      ..add(const RuntimeHostEvent(aleraRuntimeHostDisconnectedEvent, {}))
      ..add(const RuntimeHostEvent('agentChatChanged', {'chatId': 'c'}));
    await pumpEventQueue();
    await subscription.cancel();
    expect(names, <String>[
      AgentChatTransportEvents.connected,
      AgentChatTransportEvents.disconnected,
      'agentChatChanged',
    ]);
  });

  test('the runtime delivers agent chat events to the app', () {
    expect(runtimeHostEventNames, contains(AgentChatWire.changedEvent));
    expect(runtimeHostEventNames, contains(AgentChatWire.listChangedEvent));
  });

  test('chat tabs read their binding and the legacy key', () {
    WorkspaceTabRecord tab(Map<String, Object?> payload) => WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: 'ws-1',
      title: 'Chat',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      kind: WorkspaceTabKind.agentChat,
      payload: payload,
    );
    final bound = tab(<String, Object?>{
      'chatId': 'chat-1',
      'provider': 'claudeAgent',
      'model': 'opus',
    });
    expect(bound.agentChatId, 'chat-1');
    expect(bound.agentChatProvider, 'claudeAgent');
    expect(bound.agentChatModel, 'opus');
    expect(tab(<String, Object?>{'agentChatId': 'old'}).agentChatId, 'old');
    expect(tab(const <String, Object?>{}).agentChatId, isNull);
    expect(WorkspaceTabKind.tryParse('agentChat'), WorkspaceTabKind.agentChat);
    expect(agentChatProviderFallbackLabel('acpRegistry'), 'ACP Agent');
  });
}
