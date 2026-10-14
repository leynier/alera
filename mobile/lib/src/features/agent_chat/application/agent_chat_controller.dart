import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_sync.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_controller.g.dart';
part 'agent_chat_controller_history.dart';

const Uuid _uuid = Uuid();

/// One chat on the paired runtime and what the person asks of it. The runtime
/// owns the transcript and the provider process; this mirrors one and
/// forwards the other. Every mutation carries a request id the runtime
/// deduplicates, so a retry after a dropped connection never acts twice.
///
/// The notifier outlives rebuilds, so prompts still on their way survive a
/// reconnect, while the thread is always reloaded from a fresh snapshot.
@riverpod
class AgentChatController extends _$AgentChatController {
  AgentChatSync? _sync;
  AgentChatViewState? _last;

  /// Mutation ids per pending request, reused when an answer is retried.
  final Map<String, String> _responseIds = <String, String>{};

  /// The highest cursor already reported read from this phone.
  int _readCursor = 0;

  AgentChatRef get _chat =>
      AgentChatRef(chatId: chatId, workspaceId: workspaceId);

  @override
  Future<AgentChatViewState> build(
    String hostId,
    String workspaceId,
    String chatId,
  ) async {
    final repository = await ref.watch(
      agentChatRepositoryProvider(hostId).future,
    );
    final sync = AgentChatSync(
      repository: repository,
      chat: _chat,
      onChanged: _publish,
    );
    _sync = sync;
    ref.onDispose(sync.dispose);
    final view = await sync.start(previous: _last);
    _last = view;
    return view;
  }

  /// Publishes a newer view. While the build's own result is still being
  /// delivered, the update waits a microtask so that result cannot overwrite
  /// it.
  void _publish(AgentChatViewState view) {
    _last = view;
    if (!ref.mounted) return;
    if (state case AsyncData()) {
      state = AsyncData(view);
      return;
    }
    scheduleMicrotask(() {
      if (!ref.mounted || !identical(_last, view)) return;
      if (state case AsyncData(:final value) when !identical(value, view)) {
        state = AsyncData(view);
      }
    });
  }

  AgentChatSync _ready() {
    final sync = _sync;
    if (sync == null || sync.view == null) {
      throw const AgentChatConnectionException('The chat is still loading.');
    }
    return sync;
  }

  Future<void> resync() async => _sync?.resync();

  /// Sends a composed prompt; the runtime starts a turn or queues it behind
  /// the running one. Failures stay in the timeline with Retry and Edit.
  Future<void> send(AgentChatComposerDraft draft, {bool steer = false}) async {
    if (!draft.canSubmit) return;
    final sync = _ready();
    if (sync.view!.nativeOperationPending) {
      throw const AgentChatRequestException(
        message: 'The last history change has not finished yet.',
        code: AgentChatErrorCodes.nativeOperationPending,
      );
    }
    await _applyHeldModelReset(sync);
    final ids = ref
        .read(agentChatDraftStoreProvider)
        .submissionIds(hostId, chatId);
    final message = AgentChatOutgoingMessage(
      clientMessageId: ids.claim(draft.signature, _uuid.v4),
      text: draft.text,
      createdAt: DateTime.now().toUtc(),
      attachments: <AgentChatAttachment>[
        for (final attachment in draft.attachments) attachment.toAttachment(),
      ],
    );
    _putOutgoing(sync, message);
    final view = sync.view!;
    await _deliver(
      sync,
      message,
      draft.signature,
      delivery: steer && view.turnActive && view.session.capabilities.steer
          ? AgentChatDelivery.steer
          : AgentChatDelivery.auto,
    );
  }

  /// Sends a refused prompt again under its original client message id.
  Future<void> retry(String clientMessageId) async {
    final sync = _ready();
    final message = _outgoing(sync, clientMessageId);
    if (message == null) return;
    final retrying = message.withStatus(AgentChatOutgoingStatus.sending);
    _putOutgoing(sync, retrying);
    await _deliver(sync, retrying, _signature(message));
  }

  /// Takes a refused prompt out of the timeline and back into the composer.
  void edit(String clientMessageId) {
    final sync = _sync;
    final message = sync == null ? null : _outgoing(sync, clientMessageId);
    if (sync == null || message == null) return;
    final draft = AgentChatComposerDraft.fromMessage(
      message.text,
      message.attachments,
    );
    final store = ref.read(agentChatDraftStoreProvider);
    store.submissionIds(hostId, chatId).settled(draft.signature);
    store.restore(hostId, chatId, draft);
    sync.update(
      (view) => view.copyWith(
        outbox: <AgentChatOutgoingMessage>[
          for (final pending in view.outbox)
            if (pending.clientMessageId != clientMessageId) pending,
        ],
      ),
    );
  }

  Future<void> _deliver(
    AgentChatSync sync,
    AgentChatOutgoingMessage message,
    String signature, {
    AgentChatDelivery delivery = AgentChatDelivery.auto,
  }) async {
    final store = ref.read(agentChatDraftStoreProvider);
    final ids = store.submissionIds(hostId, chatId);
    final held = sync.view?.pendingModel;
    try {
      await sync.repository.send(
        AgentChatSendInput(
          chatId: chatId,
          workspaceId: workspaceId,
          clientMessageId: message.clientMessageId,
          text: message.text,
          attachments: message.attachments,
          model: held?.model,
          delivery: delivery,
        ),
      );
      ids.settled(signature);
      // A held reset stays until the chat is idle and it can be configured.
      if (held?.model != null) {
        sync.update((view) => view.copyWith(clearPendingModel: true));
      }
      _putOutgoing(sync, message.withStatus(AgentChatOutgoingStatus.accepted));
    } on Object catch (error) {
      // A connection failure may hide a send that landed, so it keeps its id
      // for a safe retry; a refusal is final and the next try is new.
      if (error is! AgentChatConnectionException) ids.settled(signature);
      if (!ref.mounted) {
        store.restore(
          hostId,
          chatId,
          AgentChatComposerDraft.fromMessage(message.text, message.attachments),
        );
        return;
      }
      _putOutgoing(
        sync,
        message.withStatus(
          AgentChatOutgoingStatus.failed,
          error: agentChatErrorMessage(error),
        ),
      );
    }
  }

  AgentChatOutgoingMessage? _outgoing(AgentChatSync sync, String id) {
    for (final message
        in sync.view?.outbox ?? const <AgentChatOutgoingMessage>[]) {
      if (message.clientMessageId == id) return message;
    }
    return null;
  }

  void _putOutgoing(AgentChatSync sync, AgentChatOutgoingMessage message) =>
      sync.update(
        (view) => view.copyWith(
          outbox: <AgentChatOutgoingMessage>[
            for (final pending in view.outbox)
              if (pending.clientMessageId != message.clientMessageId) pending,
            message,
          ],
        ),
      );

  String _signature(AgentChatOutgoingMessage message) =>
      AgentChatComposerDraft.fromMessage(
        message.text,
        message.attachments,
      ).signature;

  /// Stop stays pressed until the turn actually ends, which arrives as a
  /// change; the acknowledgement alone does not end it.
  Future<void> interrupt() async {
    final sync = _ready();
    final view = sync.view!;
    if (view.interrupting) return;
    sync.update((view) => view.copyWith(interrupting: true));
    try {
      await sync.repository.interrupt(
        _chat,
        requestId: _uuid.v4(),
        turnId: view.session.activeTurnId,
      );
    } on Object {
      sync.update((view) => view.copyWith(interrupting: false));
      rethrow;
    }
  }

  /// Answers an approval, questions or a form. Another device answering
  /// first is not a failure: the runtime already resolved the request.
  Future<void> respond(
    AgentChatRequest request,
    AgentChatResponse response,
  ) async {
    final sync = _ready();
    if (sync.view!.respondingRequestIds.contains(request.id)) return;
    sync.update(
      (view) => view.copyWith(
        respondingRequestIds: <String>{
          ...view.respondingRequestIds,
          request.id,
        },
      ),
    );
    try {
      await sync.repository.respond(
        _chat,
        requestId: _responseIds.putIfAbsent(request.id, _uuid.v4),
        runtimeRequestId: request.id,
        response: response,
      );
      _responseIds.remove(request.id);
    } on AgentChatRequestException catch (error) {
      _responseIds.remove(request.id);
      if (error.code != AgentChatErrorCodes.requestResolved) rethrow;
      unawaited(sync.resync());
    } finally {
      sync.update(
        (view) => view.copyWith(
          respondingRequestIds: <String>{
            for (final id in view.respondingRequestIds)
              if (id != request.id) id,
          },
        ),
      );
    }
  }

  /// Withdraws a message the runtime holds behind the running turn, and says
  /// whether it was still there to withdraw.
  Future<bool> cancelQueued(AgentChatQueueEntry entry) => _ready().repository
      .cancelQueued(_chat, requestId: _uuid.v4(), queueId: entry.queueId);

  /// Rewrites a queued message in place, in one runtime step, and says
  /// whether it was still queued.
  Future<bool> editQueued(AgentChatQueueEntry entry, String text) =>
      _ready().repository.lifecycle.queueEdit(
        _chat,
        requestId: _uuid.v4(),
        queueId: entry.queueId,
        text: text,
      );

  /// Moves a queued message into the running turn. The runtime does it in
  /// one step against that exact turn, so it cannot half fail.
  Future<void> steerQueued(AgentChatQueueEntry entry) async {
    final sync = _ready();
    final turnId = sync.view!.session.activeTurnId;
    if (turnId == null) return;
    await sync.repository.lifecycle.queueSteer(
      AgentChatQueueSteerInput(
        chatId: chatId,
        workspaceId: workspaceId,
        requestId: _uuid.v4(),
        queueId: entry.queueId,
        turnId: turnId,
      ),
    );
  }

  /// Tells the runtime this chat was read up to its current cursor, so the
  /// desktop and the phone agree on what is new.
  Future<void> markRead() async {
    final sync = _sync;
    final view = sync?.view;
    if (sync == null || view == null) return;
    final cursor = view.thread.cursor;
    if (cursor <= _readCursor) return;
    _readCursor = cursor;
    try {
      await sync.repository.lifecycle.markRead(
        _chat,
        requestId: _uuid.v4(),
        cursor: cursor,
      );
    } on Object {
      _readCursor = 0;
      rethrow;
    }
  }

  Future<void> loadEarlier() async {
    final sync = _ready();
    final view = sync.view!;
    final before = view.thread.historyBefore;
    if (before == null || view.loadingHistory) return;
    sync.update((view) => view.copyWith(loadingHistory: true));
    try {
      final page = await sync.repository.history(_chat, before: before);
      sync.update(
        (view) => view.copyWith(
          thread: view.thread.prependHistory(page),
          loadingHistory: false,
        ),
      );
    } on Object {
      sync.update((view) => view.copyWith(loadingHistory: false));
      rethrow;
    }
  }

  /// Model, approvals, plan mode or agent for the next turn. A switch of
  /// agent keeps the transcript and hands it to a new session; the runtime
  /// refuses it while anything is still running.
  Future<void> configure(AgentChatConfiguration configuration) async {
    if (configuration.isEmpty) return;
    final sync = _ready();
    sync.adopt(
      await sync.repository.configure(
        _chat,
        requestId: _uuid.v4(),
        configuration: configuration,
      ),
    );
  }

  /// Applies an agent and model picked in the composer. A model picked while
  /// a turn runs is held and goes out with the next message instead.
  Future<void> select(AgentChatSelection selection) async {
    final sync = _ready();
    final view = sync.view!;
    final switching =
        view.unselected ||
        selection.providerInstanceId != view.selection?.providerInstanceId;
    if (!switching && view.turnActive) {
      sync.update(
        (view) => view.copyWith(
          pendingModel: AgentChatPendingModel(model: selection.model),
        ),
      );
      return;
    }
    await configure(
      AgentChatConfiguration(
        providerInstanceId: switching ? selection.providerInstanceId : null,
        model: selection.model,
        resetModel: selection.model == null,
      ),
    );
    sync.update((view) => view.copyWith(clearPendingModel: true));
  }

  /// A held return to the provider default cannot ride on a send, which only
  /// names a model, so it is configured just before the message goes out.
  Future<void> _applyHeldModelReset(AgentChatSync sync) async {
    final held = sync.view?.pendingModel;
    if (held == null || held.model != null || sync.view!.turnActive) return;
    await configure(const AgentChatConfiguration(resetModel: true));
    sync.update((view) => view.copyWith(clearPendingModel: true));
  }

  Future<void> recover(AgentChatRecoverMode mode) async {
    final sync = _ready();
    sync.adopt(
      await sync.repository.recover(_chat, requestId: _uuid.v4(), mode: mode),
    );
  }
}
