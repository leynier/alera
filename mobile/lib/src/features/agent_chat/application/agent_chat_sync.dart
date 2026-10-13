import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:logging/logging.dart';

/// Keeps one chat current on one connection: a snapshot, then every change
/// after it, and a fresh snapshot whenever the stream cannot be trusted.
///
/// The stream is subscribed before the snapshot is read and whatever arrives
/// meanwhile is replayed onto it, so no change can fall between the two. A
/// reload does the same, which is what keeps a change that raced the reload
/// from being overwritten by an older snapshot.
class AgentChatSync({
  required final AgentChatRepository _repository,
  required final AgentChatRef _chat,
  required final void Function(AgentChatViewState view) _onChanged,
}) {
  static final Logger _logger = Logger('AgentChatSync');

  StreamSubscription<AgentChatStreamEvent>? _subscription;
  List<AgentChatStreamEvent>? _buffered;
  AgentChatViewState? _view;
  bool _started = false;
  bool _resyncing = false;
  bool _resyncQueued = false;
  bool _disposed = false;

  AgentChatViewState? get view => _view;

  AgentChatRepository get repository => _repository;

  /// Loads the chat. [previous] carries what only this phone knows, such as
  /// prompts still on their way, across a reconnect.
  Future<AgentChatViewState> start({AgentChatViewState? previous}) async {
    final buffered = <AgentChatStreamEvent>[];
    _buffered = buffered;
    _subscription = _repository.watch(_chat.chatId).listen(_onEvent);
    final snapshot = await _repository.snapshot(_chat);
    // Requests still pending on the previous connection died with it, so
    // their progress must not outlive it. A prompt it was sending becomes a
    // failed one: Retry reuses its id, so it can never start a second turn.
    _view = _withSnapshot(
      previous?.copyWith(
        loadingHistory: false,
        respondingRequestIds: const <String>{},
        outbox: <AgentChatOutgoingMessage>[
          for (final message in previous.outbox)
            message.status == AgentChatOutgoingStatus.sending
                ? message.withStatus(
                    AgentChatOutgoingStatus.failed,
                    error: agentChatErrorMessage(
                      const AgentChatConnectionException('Connection lost.'),
                    ),
                  )
                : message,
        ],
      ),
      snapshot,
    );
    _replay(buffered);
    _started = true;
    return _view!;
  }

  /// Applies a local change, such as a new outgoing prompt.
  void update(AgentChatViewState Function(AgentChatViewState view) change) {
    final view = _view;
    if (view == null || _disposed) return;
    _view = change(view);
    _notify();
  }

  /// Replaces the thread with a fresh snapshot. Requests made while one is
  /// loading collapse into a single further round.
  Future<void> resync() async {
    if (_disposed) return;
    if (_resyncing) {
      _resyncQueued = true;
      return;
    }
    _resyncing = true;
    try {
      do {
        _resyncQueued = false;
        final buffered = <AgentChatStreamEvent>[];
        _buffered = buffered;
        final AgentChatSnapshot snapshot;
        try {
          snapshot = await _repository.snapshot(_chat);
        } on Object {
          _replay(buffered);
          rethrow;
        }
        if (_disposed) return;
        _view = _withSnapshot(_view, snapshot);
        _replay(buffered);
        _notify();
      } while (_resyncQueued && !_disposed);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Could not reload chat ${_chat.chatId}.',
        error,
        stackTrace,
      );
      update((view) => view.copyWith(stale: true));
    } finally {
      _resyncing = false;
    }
  }

  /// Adopts a snapshot an action returned, unless live changes already moved
  /// past it.
  void adopt(AgentChatSnapshot snapshot) {
    final view = _view;
    if (view == null || snapshot.cursor <= view.thread.cursor) return;
    update((view) => _withSnapshot(view, snapshot));
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
  }

  AgentChatViewState _withSnapshot(
    AgentChatViewState? previous,
    AgentChatSnapshot snapshot,
  ) {
    final thread = AgentChatThread.fromSnapshot(snapshot);
    return previous == null
        ? AgentChatViewState(thread: thread)
        : previous.copyWith(thread: thread, stale: false);
  }

  void _onEvent(AgentChatStreamEvent event) {
    final buffered = _buffered;
    if (buffered != null) {
      buffered.add(event);
      return;
    }
    _apply(event);
    _notify();
  }

  void _replay(List<AgentChatStreamEvent> buffered) {
    if (identical(_buffered, buffered)) _buffered = null;
    buffered.forEach(_apply);
  }

  void _apply(AgentChatStreamEvent event) {
    final view = _view;
    if (view == null) return;
    switch (event) {
      case AgentChatChangeReceived(:final change):
        switch (view.thread.apply(change)) {
          case AgentChatApplied(:final thread):
            _view = view.copyWith(thread: thread);
          case AgentChatIgnored():
            break;
          case AgentChatGapNeedsSnapshot(:final reason):
            _logger.fine('Reloading chat ${_chat.chatId}: $reason');
            unawaited(resync());
        }
      case AgentChatResyncRequired():
        unawaited(resync());
      case AgentChatConnectionLost():
        _view = view.copyWith(stale: true);
    }
  }

  void _notify() {
    final view = _view;
    if (_started && !_disposed && view != null) _onChanged(view);
  }
}
