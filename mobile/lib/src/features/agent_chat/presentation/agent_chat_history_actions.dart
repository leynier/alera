import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';

/// What the transcript may offer on a settled turn, each present only when
/// both the runtime and the chat's agent support it: Fork From Here on an
/// answer, Rewind To Here on a prompt, View Changes on changed files, and
/// Implement In New Workspace on a proposed plan where chat tasks exist.
class const AgentChatHistoryActions({
  super.key,
  final ValueChanged<String>? onFork,
  final ValueChanged<String>? onRewind,
  final ValueChanged<String>? onViewChanges,
  final ValueChanged<AgentChatItem>? onImplementPlan,
  required super.child,
}) extends InheritedWidget {
  static AgentChatHistoryActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentChatHistoryActions>();

  // Callbacks are recreated on every build of the chat; only whether each
  // action exists changes what the transcript draws.
  @override
  bool updateShouldNotify(AgentChatHistoryActions oldWidget) =>
      (onFork == null) != (oldWidget.onFork == null) ||
      (onRewind == null) != (oldWidget.onRewind == null) ||
      (onViewChanges == null) != (oldWidget.onViewChanges == null) ||
      (onImplementPlan == null) != (oldWidget.onImplementPlan == null);
}

/// Deleting an archived chat removes its history from the host for good.
Future<bool> confirmAgentChatDelete(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => const AleraConfirmDialog(
        title: 'Delete Chat?',
        message:
            'The chat and its history are removed from the host. This cannot '
            'be undone.',
        confirmLabel: 'Delete',
        destructive: true,
      ),
    ) ??
    false;
