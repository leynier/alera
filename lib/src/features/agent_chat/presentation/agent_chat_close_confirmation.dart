import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks before closing chat tabs whose agent is still working, waiting on an
/// answer, or holding queued messages: closing archives the chat and stops
/// its provider. Unloaded chats are checked on the runtime first; an unreadable
/// chat still asks because this window cannot know whether closing stops work.
Future<bool> confirmCloseAgentChatTabs(
  BuildContext context,
  WidgetRef ref,
  Iterable<WorkspaceTabRecord> tabs,
) async {
  final work = await Future.wait(<Future<(String, bool?)>>[
    for (final tab in tabs)
      if (tab.kind == WorkspaceTabKind.agentChat)
        _hasOpenWork(ref, tab).then((busy) => (tab.title, busy)),
  ]);
  if (!context.mounted) return false;
  final busy = <String>[
    for (final (title, open) in work)
      if (open != false) title,
  ];
  if (busy.isEmpty) return true;
  final unknown = work.any((chat) => chat.$2 == null);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: busy.length == 1 ? 'Stop This Chat?' : 'Stop These Chats?',
      message: unknown
          ? busy.length == 1
                ? 'This window could not check whether ${busy.single} is still '
                      'working. Closing the tab stops the agent and archives '
                      'the chat; its history is kept.'
                : 'This window could not check whether these chats are still '
                      'working. Closing their tabs stops the agents and archives '
                      'the chats; their history is kept.'
          : busy.length == 1
          ? '${busy.single} is still working. Closing the tab stops the agent '
                'and archives the chat; its history is kept.'
          : '${busy.length} chats are still working. Closing the tabs stops '
                'their agents and archives the chats; their history is kept.',
      confirmLabel: 'Close',
      destructive: true,
    ),
  );
  return confirmed == true;
}

Future<bool?> _hasOpenWork(WidgetRef ref, WorkspaceTabRecord tab) async {
  final chatId = tab.agentChatId;
  if (chatId == null) return false;
  final provider = agentChatControllerProvider(chatId, tab.workspaceId);
  final thread = ref.exists(provider) ? ref.read(provider).thread : null;
  if (thread != null) {
    return thread.session.busy ||
        thread.pendingRequests.isNotEmpty ||
        thread.queue.isNotEmpty;
  }
  try {
    final snapshot = await ref
        .read(agentChatRepositoryProvider)
        .snapshot(AgentChatRef(chatId: chatId, workspaceId: tab.workspaceId));
    return snapshot.session.busy ||
        snapshot.pendingRequests.isNotEmpty ||
        snapshot.queue.isNotEmpty;
  } on Object {
    return null;
  }
}
