import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:flutter/material.dart';

/// What one turn changed, as the agent reported it. A report the agent
/// could not give says so; it never reads as "no changes".
Future<void> showAgentChatTurnDiffSheet(
  BuildContext context, {
  required Future<AgentChatTurnDiff> Function() load,
}) => _showLoadingSheet<AgentChatTurnDiff>(
  context,
  load: load,
  title: 'Changes',
  builder: (context, diff) {
    if (!diff.available) {
      return AleraEmptyState(
        icon: AleraIcons.gitCompare,
        title: 'Changes unavailable',
        message:
            diff.reason ?? 'The agent did not report the changes of this turn.',
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        for (final item in diff.items)
          if (item.diff case final text? when text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AleraTokens.bg,
                  border: Border.all(color: AleraTokens.borderSubtle),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                ),
                child: SingleChildScrollView(
                  scrollDirection: .horizontal,
                  padding: const EdgeInsets.all(AleraTokens.space8),
                  child: SelectableText(
                    text,
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ),
              ),
            ),
        if (diff.truncated)
          Text(
            'Only part of the changes is shown.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
      ],
    );
  },
);

/// The approvals this chat already answered, newest page first.
Future<void> showAgentChatApprovalHistorySheet(
  BuildContext context, {
  required Future<AgentChatApprovalHistoryPage> Function() load,
}) => _showLoadingSheet<AgentChatApprovalHistoryPage>(
  context,
  load: load,
  title: 'Approval History',
  builder: (context, page) => page.items.isEmpty
      ? const AleraEmptyState(
          icon: AleraIcons.success,
          title: 'No approvals yet',
          message: 'Approvals you answer in this chat are listed here.',
        )
      : ListView(
          shrinkWrap: true,
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            for (final item in page.items)
              AgentChatItemRowView(key: ValueKey<String>(item.id), item: item),
            if (page.scanLimited || page.historyBefore != null)
              Text(
                'Older approvals are not shown.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
              ),
          ],
        ),
);

Future<void> _showLoadingSheet<T>(
  BuildContext context, {
  required Future<T> Function() load,
  required String title,
  required Widget Function(BuildContext context, T value) builder,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraSectionHeader(label: title),
          Flexible(
            child: _LoadedOnce<T>(load: load, title: title, builder: builder),
          ),
        ],
      ),
    ),
  ),
);

/// Loads once per sheet, however often the sheet rebuilds for the keyboard
/// or a rotation.
class const _LoadedOnce<T>({
  required final Future<T> Function() load,
  required final String title,
  required final Widget Function(BuildContext context, T value) builder,
}) extends StatefulWidget {
  @override
  State<_LoadedOnce<T>> createState() => _LoadedOnceState<T>();
}

class _LoadedOnceState<T> extends State<_LoadedOnce<T>> {
  late final Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasData) return widget.builder(context, snapshot.data as T);
      if (snapshot.hasError) {
        return AleraEmptyState(
          icon: AleraIcons.loadFailed,
          title: 'Could not load ${widget.title.toLowerCase()}',
          message: agentChatErrorMessage(snapshot.error!),
        );
      }
      return const Padding(
        padding: AleraTokens.pagePadding,
        child: Center(child: CircularProgressIndicator()),
      );
    },
  );
}
