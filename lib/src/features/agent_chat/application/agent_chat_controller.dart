import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_controller.g.dart';
part 'agent_chat_controller_actions.dart';

// The runtime ends an interrupted turn through events; this only bounds how
// long the Stop control stays disabled if that never arrives.
const Duration _interruptSettleTimeout = Duration(seconds: 3);

/// One chat as the desktop renders it: a runtime snapshot kept current by
/// cursor-ordered changes, plus this client's in-flight actions.
@riverpod
class AgentChatController extends _$AgentChatController
    with _AgentChatComposerActions {
  @override
  late AgentChatRepository _repository;
  @override
  late AgentChatLifecycleRepository _lifecycle;
  @override
  late String Function() _nextId;
  @override
  final Map<String, String> _reconcileRequestIds = <String, String>{};
  late DateTime Function() _now;
  StreamSubscription<AgentChatStreamEvent>? _events;
  Timer? _interruptTimer;

  /// Changes that arrived while a snapshot was being read; `null` when no
  /// read is in progress.
  List<AgentChatChange>? _pending;
  bool _reloadQueued = false;
  int _loadGeneration = 0;

  @override
  AgentChatRef get _chat =>
      AgentChatRef(chatId: chatId, workspaceId: workspaceId);

  @override
  AgentChatViewState build(String chatId, String workspaceId) {
    _repository = ref.watch(agentChatRepositoryProvider);
    _lifecycle = ref.watch(agentChatLifecycleRepositoryProvider);
    _nextId = ref.watch(agentChatIdGeneratorProvider);
    _now = ref.watch(agentChatClockProvider);
    // Subscribe before the first read so no change falls in between.
    _events = _repository.watch(chatId).listen(_onEvent);
    ref.onDispose(() {
      _loadGeneration += 1;
      _interruptTimer?.cancel();
      unawaited(_events?.cancel());
    });
    _pending = <AgentChatChange>[];
    unawaited(_load());
    return const AgentChatViewState();
  }

  Future<void> retry() async {
    if (_pending != null) return;
    state = state.copyWith(phase: AgentChatPhase.loading, loadError: null);
    _pending = <AgentChatChange>[];
    await _load();
  }

  void dismissError() => state = state.copyWith(actionError: null);

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      if (!await _repository.supported()) {
        if (!_current(generation)) return;
        _pending = null;
        state = state.copyWith(phase: AgentChatPhase.unsupported);
        return;
      }
      final snapshot = await _repository.snapshot(_chat);
      if (!_current(generation)) return;
      var thread = AgentChatThread.fromSnapshot(snapshot);
      final buffered = _pending ?? const <AgentChatChange>[];
      _pending = null;
      var gap = false;
      for (final change in buffered) {
        switch (thread.apply(change)) {
          case AgentChatApplied(thread: final next):
            thread = next;
          case AgentChatIgnored():
            break;
          case AgentChatGapNeedsSnapshot():
            gap = true;
        }
        if (gap) break;
      }
      _setThread(
        thread,
        snapshotReload: true,
        phase: AgentChatPhase.ready,
        connection: AgentChatConnection.live,
      );
      if (gap || _reloadQueued) {
        _reloadQueued = false;
        _resync();
      }
    } on AgentChatUpdateRequired {
      if (!_current(generation)) return;
      _pending = null;
      state = state.copyWith(phase: AgentChatPhase.unsupported);
    } on Object catch (error) {
      if (!_current(generation)) return;
      _pending = null;
      final reconnected = _reloadQueued;
      _reloadQueued = false;
      if (reconnected) {
        // The connection came back while this read was failing.
        _resync();
        return;
      }
      if (state.thread == null) {
        state = state.copyWith(
          phase: AgentChatPhase.failed,
          loadError: agentChatErrorMessage(error),
        );
      } else {
        // Keep the last copy readable; the next reconnect reloads it.
        state = state.copyWith(
          connection: error is AgentChatConnectionException
              ? AgentChatConnection.reconnecting
              : state.connection,
          actionError: agentChatErrorMessage(error),
        );
      }
    }
  }

  bool _current(int generation) => ref.mounted && generation == _loadGeneration;

  /// Reads a fresh snapshot while the current copy stays on screen.
  void _resync() {
    // A deleted chat has no snapshot left to read.
    if (state.removed) return;
    if (_pending != null) {
      _reloadQueued = true;
      return;
    }
    _pending = <AgentChatChange>[];
    unawaited(_load());
  }

  void _onEvent(AgentChatStreamEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case AgentChatChangeReceived(:final change):
        final pending = _pending;
        if (pending != null) {
          pending.add(change);
          return;
        }
        final thread = state.thread;
        if (thread == null) return;
        switch (thread.apply(change)) {
          case AgentChatApplied(thread: final next):
            _setThread(next);
          case AgentChatIgnored():
            break;
          case AgentChatGapNeedsSnapshot():
            _resync();
        }
      case AgentChatResyncRequired():
        switch (state.phase) {
          case AgentChatPhase.ready:
            _resync();
          case AgentChatPhase.loading:
            _reloadQueued = true;
          case AgentChatPhase.failed || AgentChatPhase.unsupported:
            // A reconnect may be a restarted, newer runtime.
            unawaited(retry());
        }
      case AgentChatConnectionLost():
        state = state.copyWith(connection: AgentChatConnection.reconnecting);
      case AgentChatRemoved():
        // The surface keeps any unsent text and offers it to a new chat.
        _interruptTimer?.cancel();
        state = state.copyWith(
          removed: true,
          interrupting: false,
          pendingModel: null,
        );
    }
  }

  void _setThread(
    AgentChatThread thread, {
    bool snapshotReload = false,
    AgentChatPhase? phase,
    AgentChatConnection? connection,
  }) {
    // An accepted message missing from a full snapshot was taken back by the
    // runtime (a queued entry another client cancelled).
    final outgoing = <AgentChatOutgoingMessage>[
      for (final message in state.outgoing)
        if (!thread.containsClientMessage(message.clientMessageId) &&
            !(snapshotReload &&
                message.status == AgentChatOutgoingStatus.accepted))
          message,
    ];
    final pendingIds = <String>{
      for (final request in thread.pendingRequests) request.id,
    };
    final queueIds = <String>{for (final entry in thread.queue) entry.queueId};
    final wasBusy = state.busy;
    final interruptedTurn = state.thread?.session.activeTurnId;
    final interrupting =
        state.interrupting &&
        interruptedTurn != null &&
        thread.session.activeTurnId == interruptedTurn;
    if (!interrupting) _interruptTimer?.cancel();
    state = state.copyWith(
      phase: phase,
      connection: connection,
      thread: thread,
      projection: AgentChatTimelineProjection.build(
        thread,
        outgoing: outgoing,
        previous: state.projection,
      ),
      outgoing: outgoing,
      respondingRequestIds: _retained(state.respondingRequestIds, pendingIds),
      cancellingQueueIds: _retained(state.cancellingQueueIds, queueIds),
      interrupting: interrupting,
    );
    if (wasBusy && !state.busy) _applyPendingModel();
  }

  @override
  void _setOutgoing(List<AgentChatOutgoingMessage> outgoing) {
    final thread = state.thread;
    state = state.copyWith(
      outgoing: outgoing,
      projection: thread == null
          ? null
          : AgentChatTimelineProjection.build(
              thread,
              outgoing: outgoing,
              previous: state.projection,
            ),
    );
  }

  /// Sends a message, or queues it behind a running turn. Returns whether
  /// the composer may clear: the message is now owned by the timeline, which
  /// shows its delivery and lets the user retry it.
  bool send(
    String text, {
    List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
    AgentChatDelivery delivery = AgentChatDelivery.auto,
  }) {
    final trimmed = text.trim();
    if (!state.canSend ||
        state.nativeOperationPending ||
        (trimmed.isEmpty && attachments.isEmpty)) {
      return false;
    }
    final message = AgentChatOutgoingMessage(
      clientMessageId: _nextId(),
      text: trimmed,
      createdAt: _now().toUtc(),
      attachments: List<AgentChatAttachment>.unmodifiable(attachments),
    );
    final pending = state.pendingModel;
    // A provider default cannot travel on a message; it waits for idle.
    final model = pending?.model;
    if (model != null) state = state.copyWith(pendingModel: null);
    final firstSend = state.neverSent;
    _setOutgoing(<AgentChatOutgoingMessage>[...state.outgoing, message]);
    unawaited(
      _deliver(
        message,
        delivery == AgentChatDelivery.steer && !state.canSteer
            ? AgentChatDelivery.auto
            : delivery,
        model: model,
        firstSend: firstSend,
      ),
    );
    return true;
  }

  Future<void> retrySend(String clientMessageId) async {
    final message = state.outgoing
        .where((message) => message.clientMessageId == clientMessageId)
        .firstOrNull;
    if (message == null ||
        message.status != AgentChatOutgoingStatus.failed ||
        !state.canSend ||
        state.nativeOperationPending) {
      return;
    }
    _replaceOutgoing(message.withStatus(AgentChatOutgoingStatus.sending));
    await _deliver(message, AgentChatDelivery.auto);
  }

  Future<void> _deliver(
    AgentChatOutgoingMessage message,
    AgentChatDelivery delivery, {
    String? model,
    bool firstSend = false,
  }) async {
    // A send outlives the tab being hidden; its result must still land.
    final keepAlive = ref.keepAlive();
    try {
      await _repository.send(
        AgentChatSendInput(
          chatId: chatId,
          workspaceId: workspaceId,
          clientMessageId: message.clientMessageId,
          text: message.text,
          attachments: message.attachments,
          model: model,
          delivery: delivery,
        ),
      );
      if (!ref.mounted) return;
      if (firstSend) _rememberSelection();
      _replaceOutgoing(message.withStatus(AgentChatOutgoingStatus.accepted));
    } on Object catch (error) {
      if (!ref.mounted) return;
      _replaceOutgoing(
        message.withStatus(
          AgentChatOutgoingStatus.failed,
          error: agentChatErrorMessage(error),
        ),
      );
    } finally {
      keepAlive.close();
    }
  }

  void _replaceOutgoing(AgentChatOutgoingMessage message) {
    final thread = state.thread;
    if (thread != null &&
        thread.containsClientMessage(message.clientMessageId)) {
      _setOutgoing(<AgentChatOutgoingMessage>[
        for (final other in state.outgoing)
          if (other.clientMessageId != message.clientMessageId) other,
      ]);
      return;
    }
    _setOutgoing(<AgentChatOutgoingMessage>[
      for (final other in state.outgoing)
        other.clientMessageId == message.clientMessageId ? message : other,
    ]);
  }

  Future<void> interrupt() async {
    final turnId = state.thread?.session.activeTurnId;
    if (!state.canInterrupt || turnId == null) return;
    state = state.copyWith(interrupting: true, actionError: null);
    _interruptTimer?.cancel();
    _interruptTimer = Timer(_interruptSettleTimeout, () {
      if (ref.mounted) state = state.copyWith(interrupting: false);
    });
    await _guard(
      () => _repository.interrupt(_chat, requestId: _nextId(), turnId: turnId),
      onError: () {
        _interruptTimer?.cancel();
        state = state.copyWith(interrupting: false);
      },
    );
  }

  Future<void> respond(
    AgentChatRequest request,
    AgentChatResponse response,
  ) async {
    if (state.respondingRequestIds.contains(request.id)) return;
    state = state.copyWith(
      respondingRequestIds: <String>{...state.respondingRequestIds, request.id},
      actionError: null,
    );
    await _guard(
      () => _repository.respond(
        _chat,
        requestId: _nextId(),
        runtimeRequestId: request.id,
        response: response,
      ),
      // Another client answered first; the change removing it is on its way.
      ignoreCode: AgentChatErrorCodes.requestResolved,
      onError: () => state = state.copyWith(
        respondingRequestIds: <String>{
          for (final id in state.respondingRequestIds)
            if (id != request.id) id,
        },
      ),
    );
  }

  Future<void> recover([AgentChatRecoverMode? mode]) async {
    if (state.recovering) return;
    state = state.copyWith(recovering: true, actionError: null);
    await _guard(
      () => _repository.recover(_chat, requestId: _nextId(), mode: mode),
    );
    if (ref.mounted) state = state.copyWith(recovering: false);
  }

  Future<void> rename(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == state.thread?.title) return;
    await _guard(
      () => _repository.rename(_chat, requestId: _nextId(), title: trimmed),
    );
  }

  Future<void> loadEarlier() async {
    final thread = state.thread;
    final before = thread?.historyBefore;
    if (thread == null || before == null || state.loadingHistory) return;
    final generation = _loadGeneration;
    state = state.copyWith(loadingHistory: true);
    try {
      final page = await _repository.history(_chat, before: before);
      // A snapshot reload replaced the window this page was cut from.
      if (!_current(generation)) return;
      _setThread(state.thread!.prependHistory(page));
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(actionError: agentChatErrorMessage(error));
      }
    } finally {
      if (ref.mounted) state = state.copyWith(loadingHistory: false);
    }
  }

  @override
  Future<void> _guard(
    Future<void> Function() action, {
    String? ignoreCode,
    void Function()? onError,
  }) async {
    final keepAlive = ref.keepAlive();
    try {
      await action();
    } on Object catch (error) {
      // Resolved elsewhere; nothing to report.
      if (error is AgentChatRequestException &&
          ignoreCode != null &&
          error.code == ignoreCode) {
        return;
      }
      if (!ref.mounted) return;
      onError?.call();
      state = state.copyWith(actionError: agentChatErrorMessage(error));
    } finally {
      keepAlive.close();
    }
  }
}

/// [current] limited to [live], keeping the same set when nothing dropped so
/// widgets selecting it do not rebuild on every change.
Set<String> _retained(Set<String> current, Set<String> live) {
  if (current.every(live.contains)) return current;
  return current.intersection(live);
}
