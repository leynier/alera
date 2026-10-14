import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_direct_open.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_archived_chats_dialog.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_launcher.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a new agent chat, or reopens an archived one, in a pane group of
/// the scoped workspace. [launch] completes once the chat opened or failed,
/// so an entry can show that it is starting.
final class const AgentChatLauncher({
  required final String workspaceId,
  required final Future<AgentChatDirectOpenOutcome> Function({
    String? targetGroupId,
  })
  launch,
  required final void Function({String? targetGroupId}) openArchived,
});

/// Starts New Agent Chat for [workspace] at once, without a dialog. The new
/// chat inherits the agent of the chat the person is in, when that is a chat
/// of the same workspace and no project default applies.
Future<AgentChatDirectOpenOutcome> launchNewAgentChat(
  BuildContext context,
  WidgetRef ref, {
  required Workspace workspace,
  String? targetGroupId,
}) {
  final active = ref.read(workbenchControllerProvider).activeWorkspaceTab;
  return openNewAgentChat(
    ProviderScope.containerOf(context, listen: false),
    workspace: workspace,
    targetGroupId: targetGroupId,
    launchingChatId:
        active != null &&
            active.workspaceId == workspace.id &&
            active.kind == WorkspaceTabKind.agentChat
        ? active.agentChatId
        : null,
    onOpenProviderSettings: () {
      if (context.mounted) {
        unawaited(
          openAgentChatProviderSettings(context, hostId: workspace.hostId),
        );
      }
    },
  );
}

/// Offers "Agent Chat" and "Archived Chats" to the workbench's add-tab menus
/// below it, only while the connected runtime supports agent chats.
class const AgentChatLaunchScope({
  super.key,
  required final Workspace workspace,
  required final Widget child,
}) extends ConsumerWidget {
  static AgentChatLauncher? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AgentChatLaunchInherited>()
      ?.launcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(agentChatSupportedProvider).value ?? false;
    return _AgentChatLaunchInherited(
      launcher: supported
          ? AgentChatLauncher(
              workspaceId: workspace.id,
              launch: ({targetGroupId}) => launchNewAgentChat(
                context,
                ref,
                workspace: workspace,
                targetGroupId: targetGroupId,
              ),
              openArchived: ({targetGroupId}) => unawaited(
                showAgentChatArchivedChats(
                  context,
                  ref,
                  workspace: workspace,
                  targetGroupId: targetGroupId,
                ),
              ),
            )
          : null,
      child: child,
    );
  }
}

class const _AgentChatLaunchInherited({
  required final AgentChatLauncher? launcher,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_AgentChatLaunchInherited oldWidget) =>
      (launcher == null) != (oldWidget.launcher == null) ||
      launcher?.workspaceId != oldWidget.launcher?.workspaceId;
}
