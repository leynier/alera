import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Open Chat and Open Workspace are the only ways a chat task changes what
// the workbench shows. Each runs on a press, selects through the workbench
// controller like every other selection, and then closes Activity.

(Project, Workspace)? _placeOf(WidgetRef ref, String workspaceId) {
  final state = ref.read(workbenchControllerProvider);
  for (final project in state.projects) {
    for (final workspace in state.workspacesFor(project.id)) {
      if (workspace.id == workspaceId) return (project, workspace);
    }
  }
  return null;
}

/// Whether the workbench lists [workspaceId], so Open Workspace can work.
bool chatTaskWorkspaceKnown(WidgetRef ref, String? workspaceId) =>
    workspaceId != null && _placeOf(ref, workspaceId) != null;

Future<void> openChatTaskWorkspace(
  BuildContext context,
  WidgetRef ref,
  String workspaceId,
) async {
  final place = _placeOf(ref, workspaceId);
  if (place == null) {
    _fail(context, 'This workspace is not available in Alera.');
    return;
  }
  try {
    await ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspace(project: place.$1, workspace: place.$2);
  } on Object catch (error) {
    if (context.mounted) _fail(context, 'Could not open workspace: $error');
    return;
  }
  if (context.mounted) ref.read(activityNavigationProvider.notifier).close();
}

/// Selects the chat's tab in its workspace. An archived chat has no tab, so
/// the press reopens it first; the person asked to see that chat. With
/// [reopenArchived] false, as for a link inside an agent message, an archived
/// chat stays archived and the press only says so.
Future<void> openChatTaskChat(
  BuildContext context,
  WidgetRef ref, {
  required String chatId,
  required String workspaceId,
  bool reopenArchived = true,
}) async {
  if (_placeOf(ref, workspaceId) == null) {
    _fail(context, 'The workspace of this chat is not available in Alera.');
    return;
  }
  try {
    final (tabId, archived) = await _chatTabId(
      ref,
      chatId,
      workspaceId,
      reopenArchived: reopenArchived,
    );
    if (!context.mounted) return;
    if (archived) {
      _fail(context, 'This chat is archived. Reopen it from its workspace.');
      return;
    }
    if (tabId == null) {
      _fail(context, 'This chat no longer exists on the runtime.');
      return;
    }
    await ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspaceTab(workspaceId: workspaceId, tabId: tabId);
  } on Object catch (error) {
    if (context.mounted) {
      _fail(context, 'Could not open chat: ${agentChatErrorMessage(error)}');
    }
    return;
  }
  if (context.mounted) ref.read(activityNavigationProvider.notifier).close();
}

/// The chat's tab id, and whether the chat stayed archived instead.
Future<(String?, bool)> _chatTabId(
  WidgetRef ref,
  String chatId,
  String workspaceId, {
  required bool reopenArchived,
}) async {
  for (final tab
      in ref.read(workbenchControllerProvider).tabsFor(workspaceId)) {
    if (tab.kind == WorkspaceTabKind.agentChat && tab.agentChatId == chatId) {
      return (tab.id, false);
    }
  }
  final repository = ref.read(agentChatRepositoryProvider);
  final chats = await repository.list(
    workspaceId: workspaceId,
    includeArchived: true,
  );
  final summary = chats.where((chat) => chat.chatId == chatId).firstOrNull;
  if (summary == null) return (null, false);
  if (!summary.archived && summary.tabId != null) {
    return (summary.tabId, false);
  }
  if (summary.archived && !reopenArchived) return (null, true);
  final reopened = await repository.reopen(
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    requestId: ref.read(agentChatIdGeneratorProvider)(),
  );
  return (reopened.tabId, false);
}

void _fail(BuildContext context, String message) =>
    AleraToast.show(context, message: message, tone: AleraToastTone.error);
