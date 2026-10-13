import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/new_agent_chat_dialog.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a new agent chat in a pane group of the scoped workspace.
final class const AgentChatLauncher({
  required final String workspaceId,
  required final void Function({String? targetGroupId}) launch,
});

/// Offers "Agent Chat" to the workbench's add-tab menus below it, only while
/// the connected runtime supports agent chats.
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
              launch: ({targetGroupId}) => unawaited(
                showNewAgentChatFlow(
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
