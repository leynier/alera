import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/chat/alera_composer_banner.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:flutter/widgets.dart';

/// A queued message edited in the chat's composer. The tab sets the
/// person's draft aside here while the field holds the message's text, and
/// takes it back when the edit is saved, cancelled or overtaken. The
/// runtime edits text only, so the message keeps its attachments.
class AgentChatQueuedEdit extends ChangeNotifier {
  AgentChatQueueEntry? _entry;
  AgentChatComposerDraft? _held;
  bool _saving = false;

  AgentChatQueueEntry? get entry => _entry;
  String? get queueId => _entry?.queueId;
  bool get isEditing => _entry != null;

  /// The draft set aside; the first one stays when edits switch.
  AgentChatComposerDraft? get held => _held;

  bool get saving => _saving;
  set saving(bool value) {
    if (_saving == value) return;
    _saving = value;
    notifyListeners();
  }

  void begin(AgentChatQueueEntry entry, AgentChatComposerDraft kept) {
    _held = kept;
    _entry = entry;
    notifyListeners();
  }

  void end() {
    if (_entry == null) return;
    _entry = null;
    _held = null;
    notifyListeners();
  }
}

/// The composer's header while [entry] is edited, else `null`.
Widget? agentChatQueuedEditBanner(
  AgentChatQueuedEdit edit, {
  required VoidCallback onCancel,
}) {
  final entry = edit.entry;
  if (entry == null) return null;
  return AleraComposerBanner(
    key: const ValueKey<String>('agent-chat-queued-edit-banner'),
    title: 'Editing Queued Message',
    detail: switch (entry.attachments.length) {
      _ when edit.saving => 'Saving…',
      0 => null,
      1 => 'Its attachment stays as queued',
      final count => 'Its $count attachments stay as queued',
    },
    onCancel: edit.saving ? null : onCancel,
  );
}
