import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class CodexComposerDraft {
  const CodexComposerDraft({
    this.value = const TextEditingValue(),
    this.attachments = const <CodexInputAttachment>[],
    this.draftItems = const <CodexDraftItem>[],
  });

  final TextEditingValue value;
  final List<CodexInputAttachment> attachments;
  final List<CodexDraftItem> draftItems;

  bool get isEmpty =>
      value.text.isEmpty && attachments.isEmpty && draftItems.isEmpty;

  CodexComposerDraft copyWith({
    TextEditingValue? value,
    List<CodexInputAttachment>? attachments,
    List<CodexDraftItem>? draftItems,
  }) => CodexComposerDraft(
    value: value ?? this.value,
    attachments: attachments ?? this.attachments,
    draftItems: draftItems ?? this.draftItems,
  );
}
