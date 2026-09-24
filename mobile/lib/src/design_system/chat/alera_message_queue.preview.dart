import 'package:flutter/material.dart';

import '../alera_preview.dart';
import 'alera_message_queue.dart';
import 'alera_message_editor.dart';

@AleraPreview(name: 'Queued Messages', group: 'Chat')
Widget queuedMessagesPreview() => AleraMessageQueue(
  messages: const [
    AleraQueuedMessageRow(
      id: 'text',
      text: 'Finish the implementation and verify it',
    ),
    AleraQueuedMessageRow(
      id: 'image',
      text: 'Review this image',
      hasImage: true,
      attachmentCount: 1,
    ),
    AleraQueuedMessageRow(
      id: 'file',
      text: 'Check the attached file',
      attachmentCount: 1,
    ),
  ],
  canSteer: true,
  onEdit: (_) async {},
  onRemove: (_) async {},
  onSteer: (_) async {},
);

@AleraPreview(name: 'Edit Message', group: 'Chat')
Widget editMessagePreview() => AleraMessageEditor(
  text: 'Review the changes',
  restartsHistory: true,
  onSave: (_) async => null,
);
