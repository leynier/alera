import 'dart:async';
import 'dart:convert';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_parent_activity.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_workspace_attention.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_transitions.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_attention_notifications.g.dart';

const String _chatNotificationKind = 'agentChat';

/// The payload of a chat's OS notification. Selecting it is a press, so the
/// activation may open the chat; arrival never does.
String chatAttentionNotificationPayload(ChatAttentionEntry entry) =>
    jsonEncode(<String, String>{
      'kind': _chatNotificationKind,
      'chatId': entry.chatId,
      'workspaceId': entry.workspaceId,
      'tabId': ?entry.tabId,
    });

/// The chat tab a chat notification payload names, or null for any other
/// payload, including one without a tab.
({String workspaceId, String tabId})? decodeChatAttentionNotificationPayload(
  String payload,
) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map &&
        decoded['kind'] == _chatNotificationKind &&
        decoded['workspaceId'] is String &&
        decoded['tabId'] is String) {
      return (
        workspaceId: decoded['workspaceId'] as String,
        tabId: decoded['tabId'] as String,
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Toasts and OS notifications for chats that start waiting, stop with an
/// error or finish, once per transition. A focused window gets a toast with
/// Open Chat unless that chat is the one on screen; an unfocused one gets an
/// OS notification when the person turned agent notifications on. Child
/// chats report through their parent. Nothing here selects a workspace or a
/// tab unless the person presses Open Chat.
@Riverpod(keepAlive: true)
void chatAttentionNotificationCoordinator(Ref ref) {
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final windowActivator = ref.watch(
    agentStatusNotificationWindowActivatorProvider,
  );
  final transitions = ChatAttentionTransitions(
    now: ref.read(agentChatClockProvider),
  );
  Future<void>? initializing;
  // The presenter keeps every registered handler; each ignores the payloads
  // of the others.
  Future<void> ensureInitialized() => initializing ??= presenter.initialize(
    onSelected: (payload) {
      final target = decodeChatAttentionNotificationPayload(payload);
      if (target == null) return;
      unawaited(() async {
        await windowActivator.showAndFocus();
        if (!ref.mounted) return;
        await ref
            .read(workbenchControllerProvider.notifier)
            .selectWorkspaceTab(
              workspaceId: target.workspaceId,
              tabId: target.tabId,
            );
      }());
    },
  );
  final children = <String>{};
  void learnChildren(Iterable<AgentChatTask>? tasks) =>
      children.addAll(chatTaskChildChatIds(tasks ?? const <AgentChatTask>[]));

  ref.listen(
    chatTaskOpenTasksProvider,
    (_, next) => learnChildren(next.value?.tasks),
    fireImmediately: true,
  );
  ref.listen(
    chatTaskAttentionProvider,
    (_, next) => learnChildren(next.value?.tasks),
    fireImmediately: true,
  );
  ref.listen<Map<String, ChatAttentionEntry>>(chatAttentionLiveProvider, (
    _,
    next,
  ) {
    final notices = transitions.next(next, children: children);
    for (final (entry, notice) in notices) {
      unawaited(_deliver(ref, entry, notice, ensureInitialized));
    }
  }, fireImmediately: true);
}

Future<void> _deliver(
  Ref ref,
  ChatAttentionEntry entry,
  ChatAttentionNotice notice,
  Future<void> Function() ensureInitialized,
) async {
  final agents = ref.read(settingsControllerProvider).agents;
  if (notice == ChatAttentionNotice.done &&
      !agents.agentStatusFinishedNotificationsEnabled) {
    return;
  }
  final message = chatAttentionNoticeMessage(entry, notice);
  final focused = ref.read(inboxWindowFocusProvider).isForeground;
  if (focused) {
    final workbench = ref.read(workbenchControllerProvider);
    final onScreen =
        workbench.activeWorkspaceId == entry.workspaceId &&
        entry.tabId != null &&
        workbench.activeTabIdByWorkspace[entry.workspaceId] == entry.tabId;
    if (onScreen) return;
    final tabId = entry.tabId;
    AleraToast.publish(
      message: message,
      tone: notice == ChatAttentionNotice.failed
          ? AleraToastTone.error
          : notice == ChatAttentionNotice.needsInput
          ? AleraToastTone.warning
          : AleraToastTone.info,
      actionLabel: tabId == null ? null : 'Open Chat',
      onAction: tabId == null
          ? null
          : () => unawaited(
              ref
                  .read(workbenchControllerProvider.notifier)
                  .selectWorkspaceTab(
                    workspaceId: entry.workspaceId,
                    tabId: tabId,
                  ),
            ),
    );
    return;
  }
  if (!agents.agentStatusNotificationsEnabled) return;
  try {
    await ensureInitialized();
    await ref
        .read(agentStatusNotificationPresenterProvider)
        .show(
          AgentStatusNotification(
            // One slot per chat, so a newer notice replaces an older one.
            id: entry.chatId.hashCode & 0x3fffffff,
            title: 'Agent Chat',
            body: message,
            payload: chatAttentionNotificationPayload(entry),
          ),
        );
  } on Object {
    // The OS may refuse notifications; the sidebar and tab dots still show it.
  }
}
