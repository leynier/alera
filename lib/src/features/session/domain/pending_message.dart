import 'package:alera/src/features/session/domain/composer_attachment.dart';

class PendingMessage {
  const PendingMessage({
    required this.id,
    required this.text,
    this.attachments = const <ComposerAttachment>[],
    this.planModeEnabled = false,
  });

  final String id;
  final String text;
  final List<ComposerAttachment> attachments;
  // Plan mode captured at enqueue time, not at dequeue time.
  final bool planModeEnabled;
}
