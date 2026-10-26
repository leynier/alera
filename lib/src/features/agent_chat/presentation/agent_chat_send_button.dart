import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The composer's round action: Stop while a turn runs with an empty draft,
/// otherwise Send, whose tooltip says whether the message sends, queues or
/// steers.
class const AgentChatSendOrStopButton({
  super.key,
  required final bool hasDraft,
  required final bool canSend,
  required final bool busy,
  required final bool canSteer,
  required final bool canInterrupt,
  required final bool interrupting,
  required final VoidCallback onSend,
  required final VoidCallback onInterrupt,
  final String? sendLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (busy && !hasDraft) {
      return AleraIconButton(
        key: const ValueKey<String>('agent-chat-stop'),
        tooltip: interrupting ? 'Stopping' : 'Stop',
        icon: AleraIcons.stop,
        iconColor: AleraTokens.onAccent,
        backgroundColor: canInterrupt && !interrupting
            ? AleraTokens.accent
            : AleraTokens.surface,
        borderRadius: AleraTokens.radiusPill,
        minSize: AleraTokens.space32,
        onPressed: canInterrupt && !interrupting ? onInterrupt : null,
      );
    }
    final enabled = canSend && hasDraft;
    return AleraIconButton(
      key: const ValueKey<String>('agent-chat-send'),
      tooltip:
          sendLabel ??
          (!busy
              ? 'Send Message'
              : canSteer
              ? 'Queue Message, ${_modEnterLabel()} Steers Into This Turn'
              : 'Queue Message'),
      icon: AleraIcons.arrowUp,
      iconColor: enabled ? AleraTokens.onAccent : AleraTokens.foregroundFaint,
      backgroundColor: enabled ? AleraTokens.accent : AleraTokens.surface,
      borderRadius: AleraTokens.radiusPill,
      minSize: AleraTokens.space32,
      onPressed: enabled ? onSend : null,
    );
  }
}

String _modEnterLabel() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘Enter' : 'Ctrl+Enter';
