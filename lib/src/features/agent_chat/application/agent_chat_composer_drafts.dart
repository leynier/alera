import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';

final class const AgentChatComposerDraft({
  final String text = '',
  final List<TerminalComposerAttachment> attachments =
      const <TerminalComposerAttachment>[],
}) {
  static const AgentChatComposerDraft empty = AgentChatComposerDraft();

  bool get isEmpty => text.isEmpty && attachments.isEmpty;
}

/// In-memory drafts keyed by chat id. Drafts are deliberately not persisted:
/// they may hold paths and text the user never meant to keep.
final class AgentChatComposerDrafts {
  final Map<String, AgentChatComposerDraft> _drafts =
      <String, AgentChatComposerDraft>{};

  AgentChatComposerDraft read(String chatId) =>
      _drafts[chatId] ?? AgentChatComposerDraft.empty;

  void write(String chatId, AgentChatComposerDraft draft) {
    if (draft.isEmpty) {
      _drafts.remove(chatId);
    } else {
      _drafts[chatId] = draft;
    }
  }

  void remove(String chatId) => _drafts.remove(chatId);
}
