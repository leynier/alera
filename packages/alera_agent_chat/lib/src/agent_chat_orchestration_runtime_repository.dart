import 'dart:async';
import 'dart:math' as math;

import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_query.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_wire.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// `chatOrchestration.*` over a runtime [AgentChatTransport]. Every request
/// checks the capability first, so an older runtime fails closed with
/// [AgentChatOrchestrationUpdateRequired] and nothing is sent.
final class RuntimeAgentChatOrchestrationRepository
    implements AgentChatOrchestrationRepository {
  RuntimeAgentChatOrchestrationRepository(this._transport);

  final AgentChatTransport _transport;

  // A new workspace runs its setup before the delegation answers.
  static const Duration _delegateTimeout = Duration(minutes: 5);

  // The runtime answers a wait at its deadline; the margin covers the trip.
  static const Duration _waitMargin = Duration(seconds: 10);

  @override
  Future<bool> supported() =>
      _transport.supportsCapability(AgentChatOrchestrationWire.capability);

  Future<Map<String, Object?>> _request(
    String verb,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    if (!await supported()) throw const AgentChatOrchestrationUpdateRequired();
    return _transport.request(verb, payload, timeout: timeout);
  }

  @override
  Future<AgentChatOrchestrationCapabilities> capabilities() async =>
      AgentChatOrchestrationCapabilities.fromJson(
        await _request(
          AgentChatOrchestrationWire.capabilities,
          const <String, Object?>{},
        ),
      );

  @override
  Future<AgentChatDelegateResult> delegate(
    AgentChatDelegateInput input,
  ) async => AgentChatDelegateResult.fromJson(
    await _request(
      AgentChatOrchestrationWire.delegate,
      input.toJson(),
      timeout: _delegateTimeout,
    ),
  );

  @override
  Future<AgentChatTaskMessageResult> send(
    AgentChatTaskMessageInput input,
  ) async => AgentChatTaskMessageResult.fromJson(
    await _request(AgentChatOrchestrationWire.send, input.toJson()),
    chatId: input.chatId,
  );

  @override
  Future<AgentChatTask> task(String taskId, {bool acknowledge = false}) async {
    final response = await _request(
      AgentChatOrchestrationWire.task,
      <String, Object?>{'taskId': taskId, if (acknowledge) 'acknowledge': true},
    );
    return AgentChatTask.fromJson(response['task'] ?? response);
  }

  @override
  Future<AgentChatTaskPage> tasks(
    AgentChatTaskQuery query, {
    String? cursor,
  }) async => AgentChatTaskPage.fromJson(
    await _request(
      AgentChatOrchestrationWire.tasksList,
      query.toJson(cursor: cursor),
    ),
  );

  @override
  Future<AgentChatTaskWaitResult> wait(
    List<String> taskIds, {
    int waitSeconds = AgentChatOrchestrationWire.maxWaitSeconds,
    AgentChatTaskWaitUntil until = AgentChatTaskWaitUntil.all,
  }) async {
    final seconds = math.max(
      1,
      math.min(waitSeconds, AgentChatOrchestrationWire.maxWaitSeconds),
    );
    return AgentChatTaskWaitResult.fromJson(
      await _request(AgentChatOrchestrationWire.wait, <String, Object?>{
        'taskIds': taskIds,
        'waitSeconds': seconds,
        if (until == AgentChatTaskWaitUntil.any) 'until': until.wire,
      }, timeout: Duration(seconds: seconds) + _waitMargin),
    );
  }

  @override
  Future<AgentChatTask> cancel(
    String taskId, {
    required String requestId,
  }) async {
    final response = await _request(
      AgentChatOrchestrationWire.cancel,
      <String, Object?>{'requestId': requestId, 'taskId': taskId},
    );
    return AgentChatTask.fromJson(response['task'] ?? response);
  }

  @override
  Future<void> interrupt(String chatId, {required String requestId}) =>
      _request(AgentChatOrchestrationWire.interrupt, <String, Object?>{
        'requestId': requestId,
        'chatId': chatId,
      });

  @override
  Future<List<AgentChatTaskRequest>> requests({
    String? taskId,
    String? chatId,
  }) async => agentChatTaskRequestsFromJson(
    await _request(AgentChatOrchestrationWire.requests, <String, Object?>{
      'taskId': ?taskId,
      'chatId': ?chatId,
    }),
  );

  @override
  Future<void> respond({
    required String chatId,
    required String requestId,
    required String runtimeRequestId,
    required AgentChatResponse response,
  }) => _request(AgentChatOrchestrationWire.respond, <String, Object?>{
    'requestId': requestId,
    'chatId': chatId,
    'runtimeRequestId': runtimeRequestId,
    'response': response.toJson(),
  });

  @override
  Future<AgentChatSnapshot> configure(
    String chatId, {
    required String requestId,
    required AgentChatConfiguration configuration,
  }) async {
    // The instance names the provider; the verb takes no separate provider.
    final settings = configuration.toJson()..remove('provider');
    final response = await _request(
      AgentChatOrchestrationWire.configure,
      <String, Object?>{'requestId': requestId, 'chatId': chatId, ...settings},
      timeout: configuration.switchesProvider ? _delegateTimeout : null,
    );
    return AgentChatSnapshot.fromJson(response['snapshot']);
  }

  @override
  Future<AgentChatTranscript> read(String chatId, {int? limit}) async =>
      AgentChatTranscript.fromJson(
        await _request(AgentChatOrchestrationWire.read, <String, Object?>{
          'chatId': chatId,
          'limit': ?limit,
        }),
      );

  @override
  Future<List<AgentChatDirectoryEntry>> chats({
    String? projectId,
    String? workspaceId,
    String? hostId,
    bool includeArchived = false,
  }) async => agentChatDirectoryFromJson(
    await _request(AgentChatOrchestrationWire.list, <String, Object?>{
      'projectId': ?projectId,
      'workspaceId': ?workspaceId,
      'hostId': ?hostId,
      if (includeArchived) 'includeArchived': true,
    }),
  );

  @override
  Stream<AgentChatTaskChange> changes() => _transport.events.expand(
    (event) => switch (event.name) {
      AgentChatOrchestrationWire.changedEvent => <AgentChatTaskChange>[
        AgentChatTaskChange.fromJson(event.payload),
      ],
      AgentChatTransportEvents.connected => const <AgentChatTaskChange>[
        AgentChatTaskChange.any,
      ],
      _ => const <AgentChatTaskChange>[],
    },
  );

  @override
  Stream<AgentChatTaskPage> watchTasks(AgentChatTaskQuery query) =>
      _watch(query.mayChange, () => tasks(query));

  @override
  Stream<AgentChatTask> watchTask(String taskId) =>
      _watch((change) => change.concerns(taskId), () => task(taskId));

  /// Reads on listen and again on every relevant change, one read at a time:
  /// changes that arrive during a read fold into one more read after it.
  /// A disconnect discards the read in flight and surfaces as an error, so a
  /// list keeps its last value marked stale until the reconnect reads again.
  Stream<T> _watch<T>(
    bool Function(AgentChatTaskChange change) relevant,
    Future<T> Function() read,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<AgentChatTransportEvent>? subscription;
    var generation = 0;
    var reading = false;
    var again = false;
    var closed = false;

    Future<void> refresh() async {
      if (closed) return;
      if (reading) {
        again = true;
        return;
      }
      reading = true;
      try {
        do {
          again = false;
          final current = generation;
          try {
            final value = await read();
            if (!closed && current == generation) controller.add(value);
          } on Object catch (error, stack) {
            if (!closed && current == generation) {
              controller.addError(error, stack);
            }
          }
        } while (again && !closed);
      } finally {
        reading = false;
      }
    }

    void onEvent(AgentChatTransportEvent event) {
      switch (event.name) {
        case AgentChatTransportEvents.disconnected:
          generation++;
          controller.addError(
            const AgentChatConnectionException(
              'The Alera runtime connection closed.',
            ),
          );
        case AgentChatTransportEvents.connected:
          unawaited(refresh());
        case AgentChatOrchestrationWire.changedEvent:
          if (relevant(AgentChatTaskChange.fromJson(event.payload))) {
            unawaited(refresh());
          }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = _transport.events.listen(
          onEvent,
          onError: (Object error, StackTrace stack) {
            if (!closed) controller.addError(error, stack);
          },
        );
        unawaited(refresh());
      },
      onCancel: () async {
        closed = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
