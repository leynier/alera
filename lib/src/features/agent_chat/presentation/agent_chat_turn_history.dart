import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_item_details.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The history controls of a settled turn: Fork From Here, the rewinds the
/// runtime offers (conversation, transcript, files) and View Changes. Each
/// shows only when the surface passed its callback, which it does only when
/// the runtime and the live adapter support it, so no control appears that
/// the runtime cannot honor.
class const AgentChatTurnHistoryMenu({
  super.key,
  required final String turnId,
  required final AgentChatTimelineActions actions,
}) extends StatefulWidget {
  /// Whether [actions] offers any history control at all.
  static bool offers(AgentChatTimelineActions actions) =>
      actions.onForkTurn != null ||
      actions.onRewindTurn != null ||
      actions.onNativeRewindTurn != null ||
      actions.onRewindFilesTurn != null ||
      actions.onShowTurnDiff != null;

  @override
  State<AgentChatTurnHistoryMenu> createState() =>
      _AgentChatTurnHistoryMenuState();
}

class _AgentChatTurnHistoryMenuState extends State<AgentChatTurnHistoryMenu> {
  final AleraPopoverController _popover = AleraPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    final turnId = widget.turnId;
    final entries = <(String, ValueChanged<String>)>[
      if (actions.onForkTurn case final fork?) ('Fork From Here', fork),
      if (actions.onNativeRewindTurn case final rewind?)
        (agentChatRewindLabel(AgentChatRewindKind.conversation), rewind),
      if (actions.onRewindTurn case final rewind?)
        (agentChatRewindLabel(AgentChatRewindKind.transcript), rewind),
      if (actions.onRewindFilesTurn case final rewind?)
        (agentChatRewindLabel(AgentChatRewindKind.files), rewind),
      if (actions.onShowTurnDiff case final diff?) ('View Changes', diff),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return AleraPopover(
      controller: _popover,
      toggleOnAnchorTap: false,
      width: AleraTokens.contextMenuWidth,
      builder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (label, action) in entries)
            AleraMenuItem(
              label: label,
              selected: false,
              onTap: () {
                close();
                action(turnId);
              },
            ),
        ],
      ),
      child: AleraIconButton(
        key: ValueKey<String>('agent-chat-turn-history-$turnId'),
        tooltip: 'Turn Actions',
        icon: AleraIcons.more,
        iconSize: AleraTokens.iconSm,
        minSize: AleraTokens.iconButtonSm,
        onPressed: _popover.toggle,
      ),
    );
  }
}

/// Asks before a rewind of [kind], saying what moves and what stays.
/// Returns whether to go ahead.
Future<bool> confirmAgentChatRewindKind(
  BuildContext context,
  AgentChatRewindKind kind,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: agentChatRewindConfirmTitle(kind),
        message: agentChatRewindConfirmMessage(kind),
        confirmLabel: agentChatRewindConfirmLabel(kind),
        destructive: true,
      ),
    ) ??
    false;

/// The changes the provider reported for one turn, in a dialog. An
/// unavailable report says so rather than implying nothing changed.
Future<void> showAgentChatTurnDiff(
  BuildContext context, {
  required Future<AgentChatTurnDiff> diff,
  required ValueChanged<String> onOpenFile,
}) => showDialog<void>(
  context: context,
  builder: (context) => AleraDialog(
    maxWidth: AleraTokens.dialogWideWidth,
    maxHeight: AleraTokens.dialogMaxHeight,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            AleraTokens.space12,
            AleraTokens.space16,
            0,
          ),
          child: AleraDialogHeader(
            title: 'Turn Changes',
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: AgentChatTurnDiffView(diff: diff, onOpenFile: onOpenFile),
          ),
        ),
      ],
    ),
  ),
);

class const AgentChatTurnDiffView({
  super.key,
  required final Future<AgentChatTurnDiff> diff,
  required final ValueChanged<String> onOpenFile,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<AgentChatTurnDiff>(
      future: diff,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AleraInlineNotice(
            tone: AleraInlineNoticeTone.error,
            message: 'The changes could not be read: ${snapshot.error}',
          );
        }
        final value = snapshot.data;
        if (value == null) {
          return AleraShimmerText(
            text: 'Reading changes',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          );
        }
        if (!value.available) {
          return AleraInlineNotice(
            message:
                'The provider did not report changes for this turn.'
                '${value.reason == null ? '' : ' ${value.reason}'}',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AleraTokens.space12,
          children: <Widget>[
            if (value.items.isEmpty)
              Text(
                'The provider reported no file changes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            for (final item in value.items)
              AgentChatItemDetails(
                key: ValueKey<String>('agent-chat-turn-diff-${item.itemId}'),
                item: _asItem(item),
                onOpenFile: onOpenFile,
              ),
            if (value.truncated)
              const AleraInlineNotice(
                tone: AleraInlineNoticeTone.warning,
                message: 'Only part of the changes fit in this report.',
              ),
          ],
        );
      },
    );
  }

  static AgentChatItem _asItem(AgentChatTurnDiffItem item) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final changes = <AgentChatFileChange>[
      for (final change in item.changes) AgentChatFileChange.fromJson(change),
    ];
    return AgentChatItem(
      id: item.itemId,
      type: AgentChatItemType.fileChange,
      status: AgentChatItemStatus.completed,
      createdAt: epoch,
      updatedAt: epoch,
      changes: changes,
      output: changes.isEmpty ? item.diff ?? '' : '',
    );
  }
}
