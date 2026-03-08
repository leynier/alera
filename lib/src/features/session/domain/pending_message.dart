import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';

class PendingMessage {
  const PendingMessage({
    required this.id,
    required this.text,
    this.attachments = const <ComposerAttachment>[],
    this.draftItems = const <ComposerDraftItem>[],
    this.planModeEnabled = false,
    this.forceDefaultCollaborationMode = false,
  });

  final String id;
  final String text;
  final List<ComposerAttachment> attachments;
  final List<ComposerDraftItem> draftItems;
  // Plan mode captured at enqueue time, not at dequeue time.
  final bool planModeEnabled;
  // Explicitly reset backend collaboration mode to default on this send.
  final bool forceDefaultCollaborationMode;

  PendingMessage copyWith({
    String? id,
    String? text,
    List<ComposerAttachment>? attachments,
    List<ComposerDraftItem>? draftItems,
    bool? planModeEnabled,
    bool? forceDefaultCollaborationMode,
  }) {
    return PendingMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      draftItems: draftItems ?? this.draftItems,
      planModeEnabled: planModeEnabled ?? this.planModeEnabled,
      forceDefaultCollaborationMode:
          forceDefaultCollaborationMode ?? this.forceDefaultCollaborationMode,
    );
  }
}
