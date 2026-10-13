import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/chat/alera_message_bubble.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Outgoing', group: 'Message bubble', size: Size(560, 140))
Widget aleraMessageBubbleOutgoingPreview() => const AleraMessageBubble(
  heading: 'Question · ext:user',
  body: 'Which auth flow do you want for the CLI: device code or PKCE?',
  outgoing: true,
  statusLabel: 'Answered',
  statusTone: AleraBadgeTone.success,
  timestamp: '14:10',
);

@AleraPreview(
  name: 'Incoming new',
  group: 'Message bubble',
  size: Size(560, 140),
)
Widget aleraMessageBubbleIncomingPreview() => const AleraMessageBubble(
  heading: 'Reply · Codex',
  body: 'Device code. PKCE needs a browser on the same machine.',
  outgoing: false,
  isNew: true,
  timestamp: '14:12',
);
