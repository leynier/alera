import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_elapsed_label.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// What a person can do with a task from the dock. A null callback hides
/// its action; each runs only on a press and none of them navigates except
/// Open Chat.
class const ChatTaskDockActions({
  required final ValueChanged<AgentChatTask> onView,
  final ValueChanged<AgentChatTask>? onStop,
  final bool Function(AgentChatTask task)? canOpenChat,
  final ValueChanged<AgentChatTask>? onOpenChat,
  final VoidCallback? onViewAll,
});

/// The tasks a chat delegated, above its composer. Collapsed it is one line
/// of counts; expanded it lists the tasks, most urgent first, with Stop,
/// Open Chat and View In Activity on hover or focus. Presentational.
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
    final summary = AgentChatTaskDockSummary.of(tasks);
    final ordered = agentChatTaskDockOrder(tasks);
    final shown = ordered.take(maxRows).toList(growable: false);
    final more = ordered.length - shown.length;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    // The dock is its own Material so the toggle and rows paint their hover
    // and press ink on its surface instead of under an opaque box.
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
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                  vertical: AleraTokens.space6,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      expanded
                          ? AleraIcons.chevronDown
                          : AleraIcons.chevronRight,
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Expanded(
                      child: Text(
                        agentChatTaskDockSummaryLabel(summary),
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
          if (expanded) ...<Widget>[
            for (final task in shown)
              ChatTaskDockRow(
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
                  AleraTokens.space12,
                  0,
                  AleraTokens.space12,
                  AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('$more more', style: muted)),
                    if (actions.onViewAll != null)
                      TextButton(
                        key: const ValueKey<String>('chatTaskDockViewAll'),
                        onPressed: actions.onViewAll,
                        child: const Text('View In Activity'),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One task in the dock: agent, title, place, status and elapsed time. A
/// press on the row views it in Activity; hovering or focusing it offers
/// Stop and Open Chat as well.
class const ChatTaskDockRow({
  super.key,
  required final AgentChatTask task,
  required final DateTime Function() now,
  required final String place,
  required final ChatTaskDockActions actions,
  final bool stopping = false,
}) extends StatefulWidget {
  @override
  State<ChatTaskDockRow> createState() => _ChatTaskDockRowState();
}

class _ChatTaskDockRowState extends State<ChatTaskDockRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final actions = widget.actions;
    final show = _hovered || _focused;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final provider = task.provider;
    final openChat = actions.onOpenChat;
    final canOpen =
        openChat != null &&
        task.childChatId != null &&
        (actions.canOpenChat?.call(task) ?? true);
    final stop = actions.onStop;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: InkWell(
          onTap: () => actions.onView(task),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: AleraTokens.iconLg,
                  child: provider == null
                      ? const Icon(
                          AleraIcons.agent,
                          size: AleraTokens.iconMd,
                          color: AleraTokens.foregroundMuted,
                        )
                      : AgentChatProviderIcon(
                          provider: provider,
                          size: AleraTokens.iconMd,
                        ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisSize: .min,
                    children: <Widget>[
                      Text(
                        task.displayTitle,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        widget.place,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                // Actions replace the status while the row is hovered or
                // focused, so a narrow pane keeps the title readable.
                if (show) ...<Widget>[
                  if (stop != null && task.status.cancellable)
                    TextButton(
                      key: ValueKey<String>('chatTaskDockStop:${task.id}'),
                      onPressed: widget.stopping ? null : () => stop(task),
                      style: TextButton.styleFrom(
                        foregroundColor: AleraTokens.error,
                      ),
                      child: Text(widget.stopping ? 'Stopping…' : 'Stop'),
                    ),
                  if (canOpen)
                    TextButton(
                      key: ValueKey<String>('chatTaskDockOpenChat:${task.id}'),
                      onPressed: () => openChat(task),
                      child: const Text('Open Chat'),
                    ),
                  TextButton(
                    key: ValueKey<String>('chatTaskDockView:${task.id}'),
                    onPressed: () => actions.onView(task),
                    child: const Text('View In Activity'),
                  ),
                ] else ...<Widget>[
                  ChatTaskStatusBadge(status: task.status),
                  const SizedBox(width: AleraTokens.space8),
                  ChatTaskElapsedLabel(
                    task: task,
                    now: widget.now,
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
