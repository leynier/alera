import '../domain/codex_submission_attempts.dart';

import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'codex_composer_draft_store.g.dart';

class CodexComposerDraftStore extends ChangeNotifier {
  final Map<String, Map<String?, CodexSubmissionAttempts>> _messageAttempts =
      {};

  CodexSubmissionAttempts messageAttemptsFor(String tabId, String? threadId) {
    final threads = _messageAttempts.putIfAbsent(tabId, () => {});
    final unbound = threadId == null ? null : threads.remove(null);
    return threads.putIfAbsent(
      threadId,
      () => unbound ?? CodexSubmissionAttempts(),
    );
  }

  final Map<String, Map<String?, Map<String, String>>> _submissionIds = {};

  Map<String, String> submissionIdsFor(String tabId, String? threadId) {
    final threads = _submissionIds.putIfAbsent(tabId, () => {});
    // The first send can bind an empty chat before its acknowledgement arrives.
    final unbound = threadId == null ? null : threads.remove(null);
    return threads.putIfAbsent(threadId, () => unbound ?? {});
  }

  final Map<String, CodexComposerDraft> _drafts =
      <String, CodexComposerDraft>{};

  CodexComposerDraft read(String tabId) =>
      _drafts[tabId] ?? const CodexComposerDraft();

  void write(String tabId, CodexComposerDraft draft) {
    if (draft.isEmpty) {
      _drafts.remove(tabId);
      return;
    }
    _drafts[tabId] = draft;
  }

  void restoreSubmission(String tabId, CodexComposerDraft submission) {
    final current = read(tabId);
    final text = [
      if (current.value.text.isNotEmpty) current.value.text,
      if (submission.value.text.isNotEmpty) submission.value.text,
    ].join('\n\n');
    final offset = current.value.text.isEmpty
        ? 0
        : current.value.text.length + 2;
    write(
      tabId,
      CodexComposerDraft(
        value: TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
        attachments: [
          ...current.attachments,
          ...submission.attachments.map(
            (a) => a.tokenStart == null
                ? a
                : a.copyWith(tokenStart: a.tokenStart! + offset),
          ),
        ],
        draftItems: [
          ...current.draftItems,
          ...submission.draftItems.map(
            (d) => d.tokenStart == null
                ? d
                : d.copyWith(tokenStart: d.tokenStart! + offset),
          ),
        ],
      ),
    );
    notifyListeners();
  }

  void remove(String tabId) {
    _drafts.remove(tabId);
    _submissionIds.remove(tabId);
    _messageAttempts.remove(tabId);
  }

  void addBrowserAnnotation(String tabId, CodexInputAttachment attachment) {
    final current = read(tabId);
    if (current.attachments.any(
      (item) => item.path == attachment.path || item.id == attachment.id,
    )) {
      return;
    }
    write(
      tabId,
      current.copyWith(
        attachments: <CodexInputAttachment>[...current.attachments, attachment],
      ),
    );
    notifyListeners();
  }
}

@Riverpod(keepAlive: true)
CodexComposerDraftStore codexComposerDraftStore(Ref ref) =>
    CodexComposerDraftStore();
