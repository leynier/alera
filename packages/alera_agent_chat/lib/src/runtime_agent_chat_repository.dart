import 'dart:async';

import 'package:alera_agent_chat/src/agent_chat_change.dart';
import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_payload.dart';
import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// `agentChat.*` over a runtime [AgentChatTransport]. Every request first
/// checks the capability, so an older runtime fails closed with
/// [AgentChatUpdateRequired] instead of an unknown-request error.
final class RuntimeAgentChatRepository
    implements AgentChatRepository, AgentChatPayloadRepository {
  RuntimeAgentChatRepository(this._transport);

  final AgentChatTransport _transport;

  // Creating or reopening a chat may wait for the provider's first handshake.
  static const Duration _openTimeout = Duration(seconds: 60);

  @override
  Future<bool> supported() =>
      _transport.supportsCapability(AgentChatWire.capability);

  Future<Map<String, Object?>> _request(
    String verb,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    if (!await supported()) throw const AgentChatUpdateRequired();
    return _transport.request(verb, payload, timeout: timeout);
  }

  Map<String, Object?> _scoped(
    AgentChatRef chat, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) => <String, Object?>{
    'chatId': chat.chatId,
    'workspaceId': chat.workspaceId,
    ...payload,
  };

  @override
  Future<List<AgentChatProviderInstance>> providers({
    String? workspaceId,
    bool refreshModels = false,
  }) async => agentChatProvidersFromJson(
    await _request(AgentChatWire.providers, <String, Object?>{
      'workspaceId': ?workspaceId,
      if (refreshModels) 'refreshModels': true,
    }),
  );

  @override
  Future<List<AgentChatSummary>> list({
    String? workspaceId,
    bool includeArchived = false,
  }) async => agentChatSummariesFromJson(
    await _request(AgentChatWire.list, <String, Object?>{
      'workspaceId': ?workspaceId,
      'includeArchived': includeArchived,
    }),
  );

  @override
  Stream<AgentChatListChanged> watchList() => _transport.events
      .where(
        (event) =>
            event.name == AgentChatWire.listChangedEvent ||
            event.name == AgentChatTransportEvents.connected,
      )
      .map(
        (event) => event.name == AgentChatWire.listChangedEvent
            ? AgentChatListChanged(
                agentChatJsonString(event.payload['workspaceId']),
              )
            : const AgentChatListChanged(),
      );

  @override
  Future<AgentChatOpenResult> create(AgentChatCreateInput input) async =>
      AgentChatOpenResult.fromJson(
        await _request(
          AgentChatWire.create,
          input.toJson(),
          timeout: _openTimeout,
        ),
      );

  @override
  Future<AgentChatOpenResult> reopen(
    AgentChatRef chat, {
    required String requestId,
  }) async => AgentChatOpenResult.fromJson(
    await _request(
      AgentChatWire.reopen,
      _scoped(chat, <String, Object?>{'requestId': requestId}),
      timeout: _openTimeout,
    ),
  );

  @override
  Future<AgentChatSnapshot> snapshot(AgentChatRef chat) async =>
      AgentChatSnapshot.fromJson(
        await _request(AgentChatWire.snapshot, _scoped(chat)),
      );

  @override
  Future<AgentChatHistoryPage> history(
    AgentChatRef chat, {
    required String before,
    int? limit,
  }) async => AgentChatHistoryPage.fromJson(
    await _request(
      AgentChatWire.history,
      _scoped(chat, <String, Object?>{'before': before, 'limit': ?limit}),
    ),
  );

  @override
  Future<AgentChatPayloadPage> payload(
    AgentChatRef chat, {
    required String itemId,
    int index = 0,
    int? limit,
  }) async {
    if (itemId.trim().isEmpty || index < 0 || (limit != null && limit <= 0)) {
      throw const FormatException('Invalid retained chat payload request.');
    }
    return AgentChatPayloadPage.fromJson(
      await _request(
        AgentChatWire.payload,
        _scoped(chat, <String, Object?>{
          'itemId': itemId,
          'index': index,
          'limit': ?limit,
        }),
      ),
    );
  }

  @override
  Stream<AgentChatStreamEvent> watch(String chatId) => _transport.events.expand(
    (event) sync* {
      switch (event.name) {
        case AgentChatTransportEvents.connected:
          yield const AgentChatResyncRequired();
        case AgentChatTransportEvents.disconnected:
          yield const AgentChatConnectionLost();
        case AgentChatWire.changedEvent when event.payload['chatId'] == chatId:
          final AgentChatChange change;
          try {
            change = AgentChatChange.fromJson(event.payload);
          } on FormatException {
            // An unreadable change still advanced the runtime's cursor.
            yield const AgentChatResyncRequired();
            return;
          }
          yield AgentChatChangeReceived(change);
      }
    },
  );

  @override
  Future<AgentChatSendResult> send(AgentChatSendInput input) async =>
      AgentChatSendResult.fromJson(
        await _request(AgentChatWire.send, input.toJson()),
      );

  @override
  Future<bool> cancelQueued(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
  }) async {
    final response = await _request(
      AgentChatWire.queueCancel,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'queueId': queueId,
      }),
    );
    return agentChatJsonBool(response['cancelled']);
  }

  @override
  Future<void> interrupt(
    AgentChatRef chat, {
    required String requestId,
    String? turnId,
  }) => _request(
    AgentChatWire.interrupt,
    _scoped(chat, <String, Object?>{'requestId': requestId, 'turnId': ?turnId}),
  );

  @override
  Future<void> respond(
    AgentChatRef chat, {
    required String requestId,
    required String runtimeRequestId,
    required AgentChatResponse response,
  }) => _request(
    AgentChatWire.respond,
    _scoped(chat, <String, Object?>{
      'requestId': requestId,
      'runtimeRequestId': runtimeRequestId,
      'response': response.toJson(),
    }),
  );

  @override
  Future<AgentChatSnapshot> configure(
    AgentChatRef chat, {
    required String requestId,
    required AgentChatConfiguration configuration,
  }) async {
    final response = await _request(
      AgentChatWire.configure,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        ...configuration.toJson(),
      }),
      timeout: configuration.switchesProvider ? _openTimeout : null,
    );
    return AgentChatSnapshot.fromJson(response['snapshot']);
  }

  @override
  Future<String> rename(
    AgentChatRef chat, {
    required String requestId,
    required String title,
  }) async {
    final response = await _request(
      AgentChatWire.rename,
      _scoped(chat, <String, Object?>{'requestId': requestId, 'title': title}),
    );
    return agentChatJsonString(response['title']) ?? title;
  }

  @override
  Future<AgentChatSnapshot> recover(
    AgentChatRef chat, {
    required String requestId,
    AgentChatRecoverMode? mode,
  }) async {
    final response = await _request(
      AgentChatWire.recover,
      _scoped(chat, <String, Object?>{
        'requestId': requestId,
        'mode': ?mode?.wire,
      }),
      timeout: _openTimeout,
    );
    return AgentChatSnapshot.fromJson(response['snapshot']);
  }

  @override
  Future<void> close(AgentChatRef chat, {required String requestId}) =>
      _request(
        AgentChatWire.close,
        _scoped(chat, <String, Object?>{'requestId': requestId}),
      );
}
