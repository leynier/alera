import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class SidebarPrimaryActions extends StatelessWidget {
  const SidebarPrimaryActions({
    super.key,
    required this.canStartNewChat,
    required this.onNewChat,
    required this.onAddProject,
  });

  final bool canStartNewChat;
  final VoidCallback onNewChat;
  final VoidCallback onAddProject;

  @override
  Widget build(BuildContext context) {
    final newChatButton = FilledButton.icon(
      onPressed: canStartNewChat ? onNewChat : null,
      icon: const Icon(Icons.add, size: 16),
      label: const Text('New chat'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(34),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space8,
        AleraTokens.space12,
        AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: canStartNewChat
                ? newChatButton
                : Tooltip(
                    message: 'Add a project first',
                    child: newChatButton,
                  ),
          ),
          const SizedBox(width: AleraTokens.space8),
          IconButton(
            tooltip: 'Add project',
            onPressed: onAddProject,
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              minimumSize: const Size(34, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                side: const BorderSide(color: AleraTokens.borderSubtle),
              ),
              foregroundColor: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
