import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_composer_draft.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_catalog_selection.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_codex_composer_draft_store.g.dart';

typedef MobileCodexDraftKey = ({String hostId, String tabId});

class MobileCodexComposerDraftStore {
  final Map<MobileCodexDraftKey, MobileCodexComposerDraft> _drafts =
      <MobileCodexDraftKey, MobileCodexComposerDraft>{};
  final Set<MobileCodexDraftKey> _removed = <MobileCodexDraftKey>{};
  final Map<MobileCodexDraftKey, Set<VoidCallback>> _restoreListeners =
      <MobileCodexDraftKey, Set<VoidCallback>>{};

  void addRestoreListener(String hostId, String tabId, VoidCallback listener) =>
      _restoreListeners
          .putIfAbsent((hostId: hostId, tabId: tabId), () => <VoidCallback>{})
          .add(listener);

  void removeRestoreListener(
    String hostId,
    String tabId,
    VoidCallback listener,
  ) {
    final key = (hostId: hostId, tabId: tabId);
    final listeners = _restoreListeners[key];
    listeners?.remove(listener);
    if (listeners?.isEmpty == true) _restoreListeners.remove(key);
  }

  void activate(String hostId, String tabId) =>
      _removed.remove((hostId: hostId, tabId: tabId));

  MobileCodexComposerDraft read(String hostId, String tabId) =>
      _drafts[(hostId: hostId, tabId: tabId)] ??
      const MobileCodexComposerDraft();

  void write(String hostId, String tabId, MobileCodexComposerDraft draft) {
    final key = (hostId: hostId, tabId: tabId);
    if (_removed.contains(key)) return;
    if (draft.isEmpty) {
      _drafts.remove(key);
      return;
    }
    _drafts[key] = draft;
  }

  /// Appends an attachment that finished uploading and tells whichever
  /// composer is mounted to pick it up. An upload outlives the screen that
  /// started it: the picker sends the app to the background, and the host
  /// reconnect that follows rebuilds the tab body while the bytes are still
  /// streaming, so the state holding the composer is often gone by the time
  /// the runtime answers with the path.
  void addAttachment(
    String hostId,
    String tabId,
    Map<String, Object?> attachment,
  ) {
    final key = (hostId: hostId, tabId: tabId);
    if (_removed.contains(key)) return;
    final current = read(hostId, tabId);
    write(
      hostId,
      tabId,
      current.copyWith(
        attachments: <Map<String, Object?>>[...current.attachments, attachment],
      ),
    );
    _notifyRestore(key);
  }

  void _notifyRestore(MobileCodexDraftKey key) {
    for (final listener in List<VoidCallback>.of(
      _restoreListeners[key] ?? const <VoidCallback>{},
    )) {
      listener();
    }
  }

  void restoreSubmission(
    String hostId,
    String tabId,
    MobileCodexComposerDraft submission,
  ) {
    if (submission.isEmpty) return;
    final key = (hostId: hostId, tabId: tabId);
    if (_removed.contains(key)) return;
    final current = read(hostId, tabId);
    final currentText = current.value.text;
    final submissionText = submission.value.text;
    final submissionOffset = currentText.isEmpty ? 0 : currentText.length + 2;
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
          ...mobileCodexShiftCatalogSelections(
            submission.catalogSelections,
            submissionOffset,
          ),
        ],
      ),
    );
    _notifyRestore(key);
  }

  void remove(String hostId, String tabId) {
    final key = (hostId: hostId, tabId: tabId);
    _drafts.remove(key);
    _removed.add(key);
  }
}

@Riverpod(keepAlive: true)
MobileCodexComposerDraftStore mobileCodexComposerDraftStore(Ref ref) =>
    MobileCodexComposerDraftStore();
