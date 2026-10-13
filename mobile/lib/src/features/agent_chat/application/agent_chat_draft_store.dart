import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_draft_store.g.dart';

typedef AgentChatDraftKey = ({String hostId, String chatId});

/// Composer drafts and pending submission ids per host and chat.
///
/// Kept alive because work started from the composer outlives it: a picker
/// sends the app to the background, the host connection rebuilds on return,
/// and the chat body is rebuilt while an upload is still streaming. The
/// upload lands here and the mounted composer is told to pick it up.
class AgentChatDraftStore {
  final Map<AgentChatDraftKey, AgentChatComposerDraft> _drafts =
      <AgentChatDraftKey, AgentChatComposerDraft>{};
  final Map<AgentChatDraftKey, AgentChatSubmissionIds> _submissions =
      <AgentChatDraftKey, AgentChatSubmissionIds>{};
  final Map<AgentChatDraftKey, Set<VoidCallback>> _listeners =
      <AgentChatDraftKey, Set<VoidCallback>>{};
  final Set<AgentChatDraftKey> _closed = <AgentChatDraftKey>{};

  AgentChatComposerDraft read(String hostId, String chatId) =>
      _drafts[(hostId: hostId, chatId: chatId)] ??
      const AgentChatComposerDraft();

  void write(String hostId, String chatId, AgentChatComposerDraft draft) {
    final key = (hostId: hostId, chatId: chatId);
    if (_closed.contains(key)) return;
    if (draft.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
  }

  /// Appends a finished upload and notifies the mounted composer, if any.
  void addAttachment(
    String hostId,
    String chatId,
    AgentChatDraftAttachment attachment,
  ) {
    final current = read(hostId, chatId);
    if (current.attachments.contains(attachment)) return;
    _update(
      hostId,
      chatId,
      current.copyWith(
        attachments: <AgentChatDraftAttachment>[
          ...current.attachments,
          attachment,
        ],
      ),
    );
  }

  /// Returns a submission the runtime did not accept to the composer.
  void restore(
    String hostId,
    String chatId,
    AgentChatComposerDraft submission,
  ) => _update(hostId, chatId, read(hostId, chatId).restoring(submission));

  AgentChatSubmissionIds submissionIds(String hostId, String chatId) =>
      _submissions.putIfAbsent((
        hostId: hostId,
        chatId: chatId,
      ), AgentChatSubmissionIds.new);

  void addListener(String hostId, String chatId, VoidCallback listener) =>
      _listeners
          .putIfAbsent((hostId: hostId, chatId: chatId), () => <VoidCallback>{})
          .add(listener);

  void removeListener(String hostId, String chatId, VoidCallback listener) {
    final key = (hostId: hostId, chatId: chatId);
    final listeners = _listeners[key];
    listeners?.remove(listener);
    if (listeners?.isEmpty ?? false) _listeners.remove(key);
  }

  /// A chat is shown again, possibly after Reopen kept its id.
  void activate(String hostId, String chatId) =>
      _closed.remove((hostId: hostId, chatId: chatId));

  /// Forgets a chat that was closed, so a late upload cannot resurrect it.
  void close(String hostId, String chatId) {
    final key = (hostId: hostId, chatId: chatId);
    _drafts.remove(key);
    _submissions.remove(key);
    _closed.add(key);
  }

  void _update(String hostId, String chatId, AgentChatComposerDraft draft) {
    final key = (hostId: hostId, chatId: chatId);
    if (_closed.contains(key)) return;
    write(hostId, chatId, draft);
    for (final listener in List<VoidCallback>.of(
      _listeners[key] ?? const <VoidCallback>{},
    )) {
      listener();
    }
  }
}

@Riverpod(keepAlive: true)
AgentChatDraftStore agentChatDraftStore(Ref ref) => AgentChatDraftStore();
