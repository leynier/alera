import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Loads one page of approval history, older than `before` when given.
typedef AgentChatApprovalHistoryLoader =
    Future<AgentChatApprovalHistoryPage> Function(String? before);

/// The chat's request history (approvals, questions and forms, and what
/// became of each) in a dialog, newest page first, with older pages on
/// demand. Only shown on runtimes that advertise approval history.
Future<void> showAgentChatApprovalHistory(
  BuildContext context, {
  required AgentChatApprovalHistoryLoader load,
}) => showDialog<void>(
  context: context,
  builder: (context) => AleraDialog(
    maxWidth: AleraTokens.dialogWideWidth,
    maxHeight: AleraTokens.dialogMaxHeight,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraDialogHeader(
          title: 'Approval History',
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(child: AgentChatApprovalHistoryView(load: load)),
      ],
    ),
  ),
);

class const AgentChatApprovalHistoryView({
  super.key,
  required final AgentChatApprovalHistoryLoader load,
}) extends StatefulWidget {
  @override
  State<AgentChatApprovalHistoryView> createState() =>
      _AgentChatApprovalHistoryViewState();
}

class _AgentChatApprovalHistoryViewState
    extends State<AgentChatApprovalHistoryView> {
  final List<AgentChatItem> _items = <AgentChatItem>[];
  String? _before;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _scanLimited = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(_before);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _before = page.historyBefore;
        _scanLimited = page.scanLimited;
        _loadedOnce = true;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      shrinkWrap: true,
      children: <Widget>[
        if (_loadedOnce && _items.isEmpty)
          Text('No requests in this chat yet.', style: muted),
        for (final item in _items)
          _HistoryRow(
            key: ValueKey<String>('agent-chat-approval-history-${item.id}'),
            item: item,
          ),
        if (_scanLimited)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: Text(
              'Only recent history was searched; older requests may exist.',
              style: muted,
            ),
          ),
        if (_error case final Object error)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: AleraInlineNotice(
              tone: AleraInlineNoticeTone.error,
              message: 'The history could not be read: $error',
            ),
          ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: AleraShimmerText(text: 'Loading history', style: muted),
          )
        else if (_before != null || _error != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => unawaited(_loadMore()),
              child: Text(_error == null ? 'Load Older Requests' : 'Try Again'),
            ),
          ),
      ],
    );
  }
}

class const _HistoryRow({super.key, required final AgentChatItem item})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = agentChatJsonMap(item.normalized['approvalHistory']);
    final kind = AgentChatRequestKind.fromJson(history['kind']);
    final title = item.title?.trim();
    final response = agentChatJsonMap(history['response']);
    final decision = AgentChatApprovalDecision.tryParse(response['decision']);
    final localizations = MaterialLocalizations.of(context);
    final when = item.updatedAt.toLocal();
    final caption = <String>[
      ?_actorCaption(item.actor),
      '${localizations.formatShortMonthDay(when)} '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(when))}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AleraTokens.space2,
        children: <Widget>[
          Text(
            title == null || title.isEmpty
                ? agentChatRequestKindTitle(kind)
                : title,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            decision == null
                ? item.detail ?? 'The request is no longer pending.'
                : agentChatDecisionLabel(decision),
            style: theme.textTheme.bodySmall?.copyWith(
              color: item.isInProgress
                  ? AleraTokens.warning
                  : AleraTokens.foregroundMuted,
            ),
          ),
          Text(caption, style: AleraTokens.labelMicroFaintStyle),
        ],
      ),
    );
  }

  static String? _actorCaption(String? actor) {
    if (actor == null) return null;
    if (actor.startsWith('mobile:')) return 'From Phone';
    if (actor == 'cli') return 'From CLI';
    if (actor.startsWith('mcp:')) return 'From MCP';
    if (actor == 'desktop') return 'From Desktop';
    return null;
  }
}
