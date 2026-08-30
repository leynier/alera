import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class const CodexComposerDraft({
  final TextEditingValue value = const TextEditingValue(),
  final List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
  final List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
}) {
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
