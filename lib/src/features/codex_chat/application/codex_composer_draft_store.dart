import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';

part 'codex_composer_draft_store.g.dart';

class CodexComposerDraftStore extends ChangeNotifier {
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

  void remove(String tabId) => _drafts.remove(tabId);

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
