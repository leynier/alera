import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Open Chat and Open Workspace are the only ways a chat task leads out of
// Activity or a chat notice, and both run only on a press.

final class _OpenFailure implements Exception {
  const _OpenFailure(this.message);

  final String message;
}

Future<WorkspaceSummary> _workspace(
  WidgetRef ref,
  String hostId,
  String workspaceId,
) async {
  final client = await ref.read(workspaceClientProvider(hostId).future);
  final workspace = (await client.listWorkspaces())
      .where((item) => item.id == workspaceId)
      .firstOrNull;
  if (workspace == null) {
    throw const _OpenFailure('This workspace is no longer available.');
  }
  return workspace;
}

Future<void> openMobileChatTaskWorkspace(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required String workspaceId,
}) => _open(context, () async {
  final workspace = await _workspace(ref, hostId, workspaceId);
  return WorkspaceTabsScreen(hostId: hostId, workspace: workspace);
});

/// Pushes the chat's workspace on the chat's tab. An archived chat has no
/// tab, so the press reopens it first; the person asked to see that chat.
Future<void> openMobileChatTaskChat(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required String chatId,
  required String workspaceId,
}) => _open(context, () async {
  final workspace = await _workspace(ref, hostId, workspaceId);
  final repository = await ref.read(agentChatRepositoryProvider(hostId).future);
  final summary = (await repository.list(
    workspaceId: workspaceId,
    includeArchived: true,
  )).where((chat) => chat.chatId == chatId).firstOrNull;
  if (summary == null) {
    throw const _OpenFailure('This chat no longer exists on the runtime.');
  }
  var tabId = summary.archived ? null : summary.tabId;
  tabId ??= (await repository.reopen(
    AgentChatRef(chatId: chatId, workspaceId: workspaceId),
    requestId: ref.read(mobileChatTaskIdGeneratorProvider)(),
  )).tabId;
  return WorkspaceTabsScreen(
    hostId: hostId,
    workspace: workspace,
    initialTabId: tabId,
  );
});

Future<void> _open(
  BuildContext context,
  Future<Widget> Function() screen,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final page = await screen();
    await navigator.push<void>(MaterialPageRoute<void>(builder: (_) => page));
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error is _OpenFailure ? error.message : agentChatErrorMessage(error),
        ),
      ),
    );
  }
}
