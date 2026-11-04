import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/services.dart';

/// Where a composer attachment came from. Uploads land on the paired device's
/// disk and travel as host paths; a workspace file stays relative to the
/// workspace, which the runtime resolves against the chat's working directory.
enum AgentChatAttachmentSource { image, file, workspaceFile }

/// One attachment waiting in the composer.
class const AgentChatDraftAttachment({
  required final String path,
  required final AgentChatAttachmentSource source,
  required final String displayName,
  final String? attachmentId,
  final int? sizeBytes,
}) {
  /// A message the runtime refused comes back to the composer for Edit.
  factory fromAttachment(AgentChatAttachment attachment) =>
      AgentChatDraftAttachment(
        path: attachment.path ?? attachment.url ?? '',
        source: attachment.type.isImage ? .image : .file,
        displayName: attachment.displayName,
        attachmentId: attachment.attachmentId,
        sizeBytes: attachment.sizeBytes,
      );

  bool get isImage => source == .image;

  AgentChatAttachment toAttachment() => AgentChatAttachment(
    type: isImage ? .localImage : .file,
    path: path,
    name: displayName,
    attachmentId: attachmentId,
    sizeBytes: sizeBytes,
  );

  @override
  bool operator ==(Object other) =>
      other is AgentChatDraftAttachment &&
      other.path == path &&
      other.source == source;

  @override
  int get hashCode => Object.hash(path, source);
}

/// Composer contents for one chat: text with its selection, and attachments.
class const AgentChatComposerDraft({
  final TextEditingValue value = .empty,
  final List<AgentChatDraftAttachment> attachments =
      const <AgentChatDraftAttachment>[],
}) {
  factory fromMessage(String text, List<AgentChatAttachment> attachments) =>
      AgentChatComposerDraft(
        value: TextEditingValue(
          text: text,
          selection: .collapsed(offset: text.length),
        ),
        attachments: <AgentChatDraftAttachment>[
          for (final attachment in attachments) .fromAttachment(attachment),
        ],
      );

  String get text => value.text.trim();

  bool get isEmpty => value.text.isEmpty && attachments.isEmpty;

  /// Something worth sending: text that is not only whitespace, or a file.
  bool get canSubmit => text.isNotEmpty || attachments.isNotEmpty;

  /// Identifies a submission across retries, so resending the same prompt
  /// after a dropped connection reuses its client message id.
  String get signature => jsonEncode(<Object?>[
    text,
    for (final attachment in attachments)
      <Object?>[
        attachment.isImage,
        attachment.path,
        attachment.displayName,
        attachment.attachmentId,
        attachment.sizeBytes,
      ],
  ]);

  AgentChatComposerDraft copyWith({
    TextEditingValue? value,
    List<AgentChatDraftAttachment>? attachments,
  }) => AgentChatComposerDraft(
    value: value ?? this.value,
    attachments: attachments ?? this.attachments,
  );

  /// Puts a submission back without discarding what was typed since, so a
  /// prompt that never reached the runtime is never silently lost.
  AgentChatComposerDraft restoring(AgentChatComposerDraft submission) {
    if (submission.isEmpty) return this;
    final current = value.text;
    final restored = submission.value.text;
    final text = <String>[
      if (current.isNotEmpty) current,
      if (restored.isNotEmpty) restored,
    ].join('\n\n');
    return AgentChatComposerDraft(
      value: TextEditingValue(
        text: text,
        selection: .collapsed(offset: text.length),
      ),
      attachments: <AgentChatDraftAttachment>[
        ...attachments,
        for (final attachment in submission.attachments)
          if (!attachments.contains(attachment)) attachment,
      ],
    );
  }
}

/// Reuses one client message id per distinct submission until the runtime
/// answers it. Retrying the same text after a dropped connection must not
/// start a second turn, and the runtime deduplicates by that id.
class AgentChatSubmissionIds {
  final Map<String, String> _pending = <String, String>{};

  String claim(String signature, String Function() newId) =>
      _pending.putIfAbsent(signature, newId);

  void settled(String signature) => _pending.remove(signature);

  void settledId(String id) => _pending.removeWhere((_, value) => value == id);

  Map<String, String> get snapshot =>
      Map<String, String>.unmodifiableOf(_pending);

  void restore(Map<String, String> ids) => _pending.addAll(ids);
}
