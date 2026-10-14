import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_disclosure.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

// A running turn's "Working for" label counts seconds, so it repaints once a
// second and never per frame.
const Duration _elapsedRefresh = Duration(seconds: 1);

/// The header of a turn's work: "Working for 4s" while it runs, then "Worked
/// for 1m 5s" or how it ended. It owns the only timer of a running turn and
/// rebuilds alone on each tick.
class const AgentChatTurnHeader({
  super.key,
  required final AgentChatTurnSection section,
  required final bool expanded,
  required final VoidCallback? onToggle,
  final Widget? trailing,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTurnHeader> createState() =>
      _AgentChatTurnHeaderState();
}

class _AgentChatTurnHeaderState extends ConsumerState<AgentChatTurnHeader> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AgentChatTurnHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final live = widget.section.working && widget.section.startedAt != null;
    if (live && _ticker == null) {
      _ticker = Timer.periodic(_elapsedRefresh, (_) {
        if (mounted) setState(() {});
      });
    } else if (!live) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: section.failed ? AleraTokens.warning : AleraTokens.foregroundMuted,
    );
    final label = agentChatTurnHeaderLabel(
      section,
      now: ref.read(agentChatClockProvider)(),
    );
    final onToggle = widget.onToggle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      child: Row(
        children: <Widget>[
          AgentChatDisclosure(
            key: ValueKey<String>('agent-chat-worked-${section.turnId}'),
            expanded: widget.expanded,
            onToggle: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (section.working)
                  AleraShimmerText(text: label, style: style)
                else
                  Text(label, style: style),
                if (onToggle != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space4),
                  Icon(
                    widget.expanded
                        ? AleraIcons.chevronDown
                        : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          const Expanded(
            child: Divider(
              height: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
          ),
          if (widget.trailing case final trailing?) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            trailing,
          ],
        ],
      ),
    );
  }
}

/// What a running turn shows of its work: the current action, the first
/// sentence of the latest reasoning, and a way to the earlier actions.
class const AgentChatLiveWorkRow({
  super.key,
  required final AgentChatLiveWork live,
  required final VoidCallback? onShowEarlier,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final current = live.current;
    final reasoning = live.reasoning;
    final onShowEarlier = this.onShowEarlier;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  current == null
                      ? AleraIcons.ai
                      : agentChatWorkedActionIcon(current.kind),
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Flexible(
                  child: AleraShimmerText(
                    text: live.label,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (reasoning != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AleraTokens.space24 + AleraTokens.space4,
                right: AleraTokens.space6,
                bottom: AleraTokens.space2,
              ),
              child: Text(
                reasoning,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          if (onShowEarlier != null)
            AgentChatDisclosure(
              key: const ValueKey<String>('agent-chat-live-earlier'),
              expanded: false,
              onToggle: onShowEarlier,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    live.earlierLabel ?? 'Show Details',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  const Icon(
                    AleraIcons.chevronRight,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundFaint,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Changed Files (N)" under a settled turn, folding open to the files the
/// turn changed; each opens in the workspace.
class const AgentChatChangedFilesRow({
  super.key,
  required final String turnId,
  required final List<AgentChatFileChange> changes,
  required final AgentChatExpansion expansion,
  required final String workspacePath,
  required final ValueChanged<String> onOpenFile,
}) extends StatefulWidget {
  @override
  State<AgentChatChangedFilesRow> createState() =>
      _AgentChatChangedFilesRowState();
}

class _AgentChatChangedFilesRowState extends State<AgentChatChangedFilesRow> {
  String get _key => agentChatChangedFilesFoldKey(widget.turnId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = widget.expansion.isExpanded(_key, byDefault: false);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Padding(
      padding: const EdgeInsets.only(top: AleraTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AgentChatDisclosure(
            key: ValueKey<String>('agent-chat-changed-files-${widget.turnId}'),
            expanded: expanded,
            onToggle: () =>
                setState(() => widget.expansion.set(_key, expanded: !expanded)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  AleraIcons.edit,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Text(
                  agentChatChangedFilesLabel(widget.changes.length),
                  style: style,
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
          if (expanded)
            for (final change in widget.changes)
              _ChangedFileRow(
                key: ValueKey<String>('agent-chat-changed-${change.path}'),
                change: change,
                workspacePath: widget.workspacePath,
                onOpen: () => widget.onOpenFile(
                  p.isAbsolute(change.path) || widget.workspacePath.isEmpty
                      ? change.path
                      : p.join(widget.workspacePath, change.path),
                ),
              ),
        ],
      ),
    );
  }
}

class const _ChangedFileRow({
  super.key,
  required final AgentChatFileChange change,
  required final String workspacePath,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = change.lineCounts;
    final relative =
        workspacePath.isNotEmpty && p.isWithin(workspacePath, change.path)
        ? p.relative(change.path, from: workspacePath)
        : change.path;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AleraTokens.space24,
          right: AleraTokens.space6,
          top: AleraTokens.space2,
          bottom: AleraTokens.space2,
        ),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: change.path,
              kind: AleraFileIconKind.file,
              size: AleraTokens.iconMd,
            ),
            const SizedBox(width: AleraTokens.space6),
            Flexible(
              child: Text(
                relative,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AleraTokens.monoCompactStyle.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
            ),
            if (counts.additions > 0 || counts.deletions > 0) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              Text(
                '+${counts.additions}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.success,
                ),
              ),
              const SizedBox(width: AleraTokens.space4),
              Text(
                '-${counts.deletions}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
