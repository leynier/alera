import 'package:alera/src/design_system/chat/alera_composer_banner.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';

/// Saves an edited queued message; `null` when the runtime took it, else the
/// reason to show.
typedef AgentChatQueuedEditSave = Future<String?> Function(
  String queueId,
  String text,
);

/// What became of an edit whose message left the queue before it was saved.
enum AgentChatQueuedEditLoss {
  /// The edit was unchanged; nothing to say.
  none,

  /// The changed text stayed in the composer as the new draft.
  kept,

  /// The person's own draft came back and the changed text was dropped.
  discarded,
}

/// A queued message edited in the chat's own composer. Beginning an edit
/// sets the person's draft aside and puts the message's text in the field;
/// saving or cancelling brings the draft back. The runtime edits text only,
/// so the message keeps its attachments, and files added during the edit
/// return with the draft instead of being lost.
class AgentChatQueuedEdit extends ChangeNotifier {
  AgentChatQueuedEdit(this._composer);

  final TerminalComposerController _composer;
  String? _queueId;
  String _originalText = '';
  int _attachmentCount = 0;
  AgentChatComposerDraft? _held;
  bool _saving = false;

  TerminalComposerController get composer => _composer;
  String? get queueId => _queueId;
  bool get isEditing => _queueId != null;
  bool get saving => _saving;

  /// How many attachments the edited message keeps.
  int get attachmentCount => _attachmentCount;

  /// The draft set aside while editing; this, not the field, is the chat's
  /// draft to persist until the edit ends.
  AgentChatComposerDraft? get heldDraft => _held == null
      ? null
      : AgentChatComposerDraft(
          text: _held!.text,
          attachments: List.unmodifiable(<TerminalComposerAttachment>[
            ..._held!.attachments,
            ..._composer.attachments,
          ]),
        );

  void begin(AgentChatQueueEntry entry) {
    if (_saving) return;
    if (_queueId != entry.queueId) {
      // Switching edits keeps the first draft and any files added since.
      _held =
          heldDraft ??
          AgentChatComposerDraft(
            text: _composer.textController.text,
            attachments: List.unmodifiable(_composer.attachments),
          );
      _queueId = entry.queueId;
      _originalText = entry.text;
      _attachmentCount = entry.attachments.length;
      _show(entry.text, const <TerminalComposerAttachment>[]);
      notifyListeners();
    }
    _composer.focusNode.requestFocus();
  }

  void cancel() {
    if (!isEditing || _saving) return;
    _finish();
    _composer.focusNode.requestFocus();
  }

  /// Saves the field as the message's text; on success the draft returns.
  Future<String?> save(AgentChatQueuedEditSave save) async {
    final queueId = _queueId;
    if (queueId == null || _saving) return null;
    final text = _composer.textController.text;
    if (text.trim().isEmpty && _attachmentCount == 0) {
      return 'A queued message needs text or attachments.';
    }
    _saving = true;
    notifyListeners();
    final String? error;
    try {
      error = await save(queueId, text);
    } finally {
      _saving = false;
    }
    if (error == null && _queueId == queueId) {
      _finish();
    } else {
      notifyListeners();
    }
    return error;
  }

  /// Ends an edit whose message the runtime no longer holds (it ran, was
  /// steered or was removed elsewhere). A changed edit becomes the draft when
  /// the person had none; otherwise their draft wins.
  AgentChatQueuedEditLoss reconcile(List<AgentChatQueueEntry> queue) {
    final queueId = _queueId;
    if (queueId == null ||
        _saving ||
        queue.any((entry) => entry.queueId == queueId)) {
      return AgentChatQueuedEditLoss.none;
    }
    final changed = _composer.textController.text != _originalText;
    if (changed && (_held?.isEmpty ?? true)) {
      _clear();
      notifyListeners();
      return AgentChatQueuedEditLoss.kept;
    }
    _finish();
    return changed
        ? AgentChatQueuedEditLoss.discarded
        : AgentChatQueuedEditLoss.none;
  }

  void _finish() {
    final draft = heldDraft ?? AgentChatComposerDraft.empty;
    _clear();
    _show(draft.text, draft.attachments);
    notifyListeners();
  }

  void _clear() {
    _queueId = null;
    _originalText = '';
    _attachmentCount = 0;
    _held = null;
  }

  void _show(String text, List<TerminalComposerAttachment> attachments) {
    _composer.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _composer.removeAttachments(<String>[
      for (final attachment in _composer.attachments) attachment.id,
    ]);
    for (final attachment in attachments) {
      _composer.addAttachment(
        kind: attachment.kind,
        path: attachment.path,
        displayName: attachment.displayName,
        localSourcePath: attachment.localSourcePath,
        attachmentId: attachment.attachmentId,
        sizeBytes: attachment.sizeBytes,
      );
    }
  }
}

/// The composer's header while [edit] is in progress, else `null`.
Widget? agentChatQueuedEditBanner(AgentChatQueuedEdit? edit) {
  if (edit == null || !edit.isEditing) return null;
  return AleraComposerBanner(
    key: const ValueKey<String>('agent-chat-queued-edit-banner'),
    title: 'Editing Queued Message',
    detail: edit.saving
        ? 'Saving…'
        : switch (edit.attachmentCount) {
            0 => 'Send saves it in place',
            1 => 'Its attachment stays as queued',
            final count => 'Its $count attachments stay as queued',
          },
    cancelShortcutLabel: 'Esc',
    onCancel: edit.saving ? null : edit.cancel,
  );
}

/// Saves [edit] through [save] and reports a refusal as an error toast.
Future<void> saveAgentChatQueuedEdit(
  AgentChatQueuedEdit edit,
  AgentChatQueuedEditSave save,
) async {
  final error = await edit.save(save);
  if (error != null) AleraToast.publish(message: error, tone: .error);
}
