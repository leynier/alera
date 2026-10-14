import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:flutter/material.dart';

/// Lets the person pick one of the rewinds [options] offers and confirm it.
/// With a single choice it goes straight to the confirmation. Returns the
/// confirmed kind, or null when they back out. It runs nothing itself; the
/// caller performs the rewind the person chose.
Future<AgentChatRewindKind?> showAgentChatRewindSheet(
  BuildContext context, {
  required AgentChatRewindOptions options,
}) async {
  final kinds = options.kinds;
  if (kinds.isEmpty) return null;
  final kind = kinds.length == 1
      ? kinds.single
      : await showModalBottomSheet<AgentChatRewindKind>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: <Widget>[
                const AleraSectionHeader(label: 'Rewind'),
                for (final kind in kinds)
                  ListTile(
                    key: ValueKey<String>('agent-chat-rewind-${kind.name}'),
                    leading: Icon(
                      kind == AgentChatRewindKind.files
                          ? AleraIcons.files
                          : AleraIcons.restore,
                      size: AleraTokens.iconMd,
                    ),
                    title: Text(agentChatRewindLabel(kind)),
                    subtitle: Text(agentChatRewindDescription(kind)),
                    onTap: () => Navigator.of(context).pop(kind),
                  ),
                const SizedBox(height: AleraTokens.space8),
              ],
            ),
          ),
        );
  if (kind == null || !context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: agentChatRewindConfirmTitle(kind),
      message: agentChatRewindConfirmMessage(kind),
      confirmLabel: agentChatRewindConfirmLabel(kind),
      destructive: true,
    ),
  );
  return (confirmed ?? false) ? kind : null;
}
