import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';

/// An in-memory [AgentChatRepository] that records every call and lets a test
/// decide each answer and push stream events.
final class FakeAgentChatRepository implements AgentChatRepository {
  FakeAgentChatRepository({this.isSupported = true});

  bool isSupported;
  final List<(String, Object?)> calls = <(String, Object?)>[];
  final StreamController<AgentChatStreamEvent> events =
      StreamController<AgentChatStreamEvent>.broadcast();
  final StreamController<AgentChatListChanged> listEvents =
      StreamController<AgentChatListChanged>.broadcast();

  /// Answers `snapshot` in order; the last one repeats.
  final List<FutureOr<AgentChatSnapshot> Function()> snapshots =
      <FutureOr<AgentChatSnapshot> Function()>[];
  int snapshotReads = 0;
  List<AgentChatProviderInstance> providerCatalog =
      const <AgentChatProviderInstance>[];
  Object? sendError;
  Object? respondError;
  Object? configureError;
  Completer<void>? sendGate;
  Completer<void>? createGate;
  Completer<void>? reopenGate;
  AgentChatOpenResult? createResult;
  AgentChatOpenResult? reopenResult;
  List<AgentChatSummary> summaries = const <AgentChatSummary>[];

  void emitChange(Map<String, Object?> payload) =>
      events.add(AgentChatChangeReceived(AgentChatChange.fromJson(payload)));

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<List<AgentChatProviderInstance>> providers({
    String? workspaceId,
    bool refreshModels = false,
  }) async {
    calls.add(('providers', workspaceId));
    return providerCatalog;
  }

  @override
  Future<List<AgentChatSummary>> list({
    String? workspaceId,
    bool includeArchived = false,
  }) async {
    calls.add(('list', (workspaceId, includeArchived)));
    return summaries;
  }

  @override
  Stream<AgentChatListChanged> watchList() => listEvents.stream;

  @override
  Future<AgentChatOpenResult> create(AgentChatCreateInput input) async {
    calls.add(('create', input));
    await createGate?.future;
    return createResult ?? (throw StateError('No create result configured.'));
  }

  @override
  Future<AgentChatOpenResult> reopen(
    AgentChatRef chat, {
    required String requestId,
  }) async {
    calls.add(('reopen', (chat.chatId, requestId)));
    await reopenGate?.future;
    return reopenResult ?? (throw StateError('No reopen result configured.'));
  }

  @override
  Future<AgentChatSnapshot> snapshot(AgentChatRef chat) async {
    calls.add(('snapshot', chat.chatId));
    final index = snapshotReads < snapshots.length
        ? snapshotReads
        : snapshots.length - 1;
    snapshotReads += 1;
    return snapshots[index]();
  }

  @override
  Future<AgentChatHistoryPage> history(
    AgentChatRef chat, {
    required String before,
    int? limit,
  }) async {
    calls.add(('history', before));
    return const AgentChatHistoryPage();
  }

  @override
  Stream<AgentChatStreamEvent> watch(String chatId) => events.stream;

  @override
  Future<AgentChatSendResult> send(AgentChatSendInput input) async {
    calls.add(('send', input));
    await sendGate?.future;
    final error = sendError;
    if (error != null) throw error;
    return const AgentChatSendResult(delivery: AgentChatSendDelivery.started);
  }

  @override
  Future<bool> cancelQueued(
    AgentChatRef chat, {
    required String requestId,
    required String queueId,
  }) async {
    calls.add(('cancelQueued', queueId));
    return true;
  }

  @override
  Future<void> interrupt(
    AgentChatRef chat, {
    required String requestId,
    String? turnId,
  }) async => calls.add(('interrupt', turnId));

  @override
  Future<void> respond(
    AgentChatRef chat, {
    required String requestId,
    required String runtimeRequestId,
    required AgentChatResponse response,
  }) async {
    calls.add(('respond', (runtimeRequestId, response)));
    final error = respondError;
    if (error != null) throw error;
  }

  @override
  Future<AgentChatSnapshot> configure(
    AgentChatRef chat, {
    required String requestId,
    required AgentChatConfiguration configuration,
  }) async {
    calls.add(('configure', configuration));
    final error = configureError;
    if (error != null) throw error;
    return snapshots.last();
  }

  @override
  Future<String> rename(
    AgentChatRef chat, {
    required String requestId,
    required String title,
  }) async {
    calls.add(('rename', title));
    return title;
  }

  @override
  Future<AgentChatSnapshot> recover(
    AgentChatRef chat, {
    required String requestId,
    AgentChatRecoverMode? mode,
  }) async {
    calls.add(('recover', mode));
    return snapshots.last();
  }

  @override
  Future<void> close(AgentChatRef chat, {required String requestId}) async =>
      calls.add(('close', chat.chatId));
}

/// A snapshot fixture with sensible defaults; [items] and [requests] are raw
/// runtime JSON so tests read like the wire.
AgentChatSnapshot agentChatSnapshotFixture({
  int cursor = 1,
  String status = 'ready',
  String? activeTurnId,
  List<Map<String, Object?>> items = const <Map<String, Object?>>[],
  List<Map<String, Object?>> turns = const <Map<String, Object?>>[],
  List<Map<String, Object?>> requests = const <Map<String, Object?>>[],
  List<Map<String, Object?>> queue = const <Map<String, Object?>>[],
  Map<String, Object?>? recovery,
  List<Map<String, Object?>> commands = const <Map<String, Object?>>[],
  Map<String, Object?>? goal,
  Map<String, Object?> capabilities = const <String, Object?>{
    'interrupt': true,
    'approvals': true,
    'userInput': true,
    'plan': true,
  },
}) => AgentChatSnapshot.fromJson(<String, Object?>{
  'chatId': 'chat-1',
  'workspaceId': 'ws-1',
  'tabId': 'tab-1',
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'title': 'Fix the build',
  'cursor': cursor,
  'session': <String, Object?>{
    'status': status,
    'model': 'gpt-5',
    'runtimeMode': 'approval-required',
    'interactionMode': 'default',
    'activeTurnId': ?activeTurnId,
    'capabilities': capabilities,
    'commands': commands,
    'goal': ?goal,
  },
  'turns': turns,
  'items': items,
  'pendingRequests': requests,
  'queue': queue,
  'recovery': ?recovery,
});

Map<String, Object?> agentChatItemFixture(
  String id,
  String type, {
  String? turnId = 'turn-1',
  String text = '',
  String status = 'completed',
  String? clientMessageId,
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': status,
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:05Z',
  'text': text,
  'clientMessageId': ?clientMessageId,
  'normalized': normalized,
};
