import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_tiles.dart';
import 'package:flutter/material.dart';

/// What a person can do with a task from the dock. A null callback hides its
/// action; Open Chat is the only one that leaves the chat.
class const ChatTaskDockActions({
  required final ValueChanged<AgentChatTask> onView,
  final ValueChanged<AgentChatTask>? onStop,
  final bool Function(AgentChatTask task)? canOpenChat,
  final ValueChanged<AgentChatTask>? onOpenChat,
});

enum _RowAction { stop, openChat, view }

/// The tasks a chat delegated, above its composer: one line of counts that
/// expands into the tasks, most urgent first. A tap opens a task; its menu
/// offers Stop and Open Chat. Presentational.
class const ChatTaskDockView({
  super.key,
  required final List<AgentChatTask> tasks,
  required final bool expanded,
  required final ValueChanged<bool> onExpandedChanged,
  required final DateTime Function() now,
  required final String Function(AgentChatTask task) placeOf,
  required final ChatTaskDockActions actions,
  final Set<String> stopping = const <String>{},
  final int maxRows = defaultMaxRows,
}) extends StatelessWidget {
  static const int defaultMaxRows = 5;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final ordered = agentChatTaskDockOrder(tasks);
    final shown = ordered.take(maxRows).toList(growable: false);
    final more = ordered.length - shown.length;
    // The dock is its own Material so the toggle and the task tiles paint
    // their ink on its surface instead of under an opaque box.
    return Material(
      key: const ValueKey<String>('chatTaskDock'),
      color: AleraTokens.surfaceVariant,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              key: const ValueKey<String>('chatTaskDockToggle'),
              onTap: () => onExpandedChanged(!expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AleraTokens.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.spaceMd,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        expanded
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronRight,
                        size: AleraTokens.iconSm,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.spaceSm),
                      Expanded(
                        child: Text(
                          agentChatTaskDockSummaryLabel(
                            AgentChatTaskDockSummary.of(tasks),
                          ),
                          key: const ValueKey<String>('chatTaskDockSummary'),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (expanded) ...<Widget>[
            for (final task in shown)
              _DockRow(
                key: ValueKey<String>('chatTaskDockRow:${task.id}'),
                task: task,
                now: now,
                place: placeOf(task),
                stopping: stopping.contains(task.id),
                actions: actions,
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.spaceMd,
                  0,
                  AleraTokens.spaceMd,
                  AleraTokens.spaceSm,
                ),
                child: Text('$more more in Activity', style: muted),
              ),
          ],
        ],
      ),
    );
  }
}

class const _DockRow({
  super.key,
  required final AgentChatTask task,
  required final DateTime Function() now,
  required final String place,
  required final bool stopping,
  required final ChatTaskDockActions actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openChat = actions.onOpenChat;
    final canOpen =
        openChat != null &&
        task.childChatId != null &&
        (actions.canOpenChat?.call(task) ?? true);
    final stop = actions.onStop;
    final canStop = stop != null && task.status.cancellable && !stopping;
    final agent = chatTaskAgentLabel(task);
    return ListTile(
      minTileHeight: AleraTokens.minTapTarget,
      contentPadding: const EdgeInsets.only(left: AleraTokens.spaceMd),
      title: Text(
        task.displayTitle,
        maxLines: 1,
        overflow: .ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Row(
        children: <Widget>[
          ChatTaskStatusBadge(status: task.status),
          const SizedBox(width: AleraTokens.spaceSm),
          _Elapsed(task: task, now: now),
          const SizedBox(width: AleraTokens.spaceSm),
          Expanded(
            child: Text(
              <String>[if (agent.isNotEmpty) agent, place].join(' · '),
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ),
        ],
      ),
      onTap: () => actions.onView(task),
      trailing: PopupMenuButton<_RowAction>(
        key: ValueKey<String>('chatTaskDockMenu:${task.id}'),
        tooltip: 'Task Actions',
        icon: const Icon(AleraIcons.more),
        onSelected: (action) {
          switch (action) {
            case _RowAction.stop:
              stop?.call(task);
            case _RowAction.openChat:
              openChat?.call(task);
            case _RowAction.view:
              actions.onView(task);
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<_RowAction>>[
          if (canStop)
            const PopupMenuItem<_RowAction>(
              value: _RowAction.stop,
              child: Text('Stop'),
            ),
          if (canOpen)
            const PopupMenuItem<_RowAction>(
              value: _RowAction.openChat,
              child: Text('Open Chat'),
            ),
          const PopupMenuItem<_RowAction>(
            value: _RowAction.view,
            child: Text('View Task'),
          ),
        ],
      ),
    );
  }
}

/// Elapsed time of a task, ticking once a second only while it runs and is
/// on screen.
class const _Elapsed({
  required final AgentChatTask task,
  required final DateTime Function() now,
}) extends StatefulWidget {
  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  static const Duration _tick = Duration(seconds: 1);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Elapsed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.task.status.settled) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(_tick, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    agentChatDurationLabel(agentChatTaskElapsed(widget.task, widget.now())),
  );
}
