import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_composer_draft.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_codex_composer_draft_store.g.dart';

typedef MobileCodexDraftKey = ({String hostId, String tabId});

class MobileCodexComposerDraftStore {
  final Map<MobileCodexDraftKey, MobileCodexComposerDraft> _drafts =
      <MobileCodexDraftKey, MobileCodexComposerDraft>{};

  MobileCodexComposerDraft read(String hostId, String tabId) =>
      _drafts[(hostId: hostId, tabId: tabId)] ??
      const MobileCodexComposerDraft();

  void write(String hostId, String tabId, MobileCodexComposerDraft draft) {
    final key = (hostId: hostId, tabId: tabId);
    if (draft.isEmpty) {
      _drafts.remove(key);
      return;
    }
    _drafts[key] = draft;
  }

  void restoreSubmission(
    String hostId,
    String tabId,
    MobileCodexComposerDraft submission,
  ) {
    if (submission.isEmpty) return;
    final current = read(hostId, tabId);
    final currentText = current.value.text;
    final submissionText = submission.value.text;
    final mergedText = <String>[
      if (currentText.isNotEmpty) currentText,
      if (submissionText.isNotEmpty) submissionText,
    ].join('\n\n');
    write(
      hostId,
      tabId,
      MobileCodexComposerDraft(
        value: TextEditingValue(
          text: mergedText,
          selection: TextSelection.collapsed(offset: mergedText.length),
        ),
        attachments: <Map<String, Object?>>[
          ...current.attachments,
          ...submission.attachments,
        ],
        catalogSelections: <Map<String, Object?>>[
          ...current.catalogSelections,
          ...submission.catalogSelections,
        ],
      ),
    );
  }

  void remove(String hostId, String tabId) =>
      _drafts.remove((hostId: hostId, tabId: tabId));
}

@Riverpod(keepAlive: true)
MobileCodexComposerDraftStore mobileCodexComposerDraftStore(Ref ref) =>
    MobileCodexComposerDraftStore();
