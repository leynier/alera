import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks before closing chat tabs whose agent is still working, waiting on an
/// answer, or holding queued messages: closing archives the chat and stops
/// its provider. Chats whose state this window has not loaded close without
/// asking, since nothing here knows they are busy.
Future<bool> confirmCloseAgentChatTabs(
  BuildContext context,
  WidgetRef ref,
  Iterable<WorkspaceTabRecord> tabs,
) async {
  final busy = <String>[
    for (final tab in tabs)
      if (tab.kind == WorkspaceTabKind.agentChat && _hasOpenWork(ref, tab))
        tab.title,
  ];
  if (busy.isEmpty) return true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: busy.length == 1 ? 'Stop This Chat?' : 'Stop These Chats?',
      message: busy.length == 1
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

bool _hasOpenWork(WidgetRef ref, WorkspaceTabRecord tab) {
  final chatId = tab.agentChatId;
  if (chatId == null) return false;
  final provider = agentChatControllerProvider(chatId, tab.workspaceId);
  if (!ref.exists(provider)) return false;
  final thread = ref.read(provider).thread;
  return thread != null &&
      (thread.session.busy ||
          thread.pendingRequests.isNotEmpty ||
          thread.queue.isNotEmpty);
}
