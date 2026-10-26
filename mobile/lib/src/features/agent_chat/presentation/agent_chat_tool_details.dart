import 'dart:convert';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:flutter/material.dart';

/// Long command output and tool payloads are cut to their tail: the end is
/// where errors and results are, and laying out megabytes of text on the UI
/// isolate would stall the timeline.
const int _maxDetailCharacters = 12000;

/// What an activity item did, in full: the command and its output, the files
/// it changed, or the tool call's input and result.
class const AgentChatToolDetails({super.key, required final AgentChatItem item})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      if (item.type == AgentChatItemType.reasoning)
        _reasoning(item)
      else ...<Widget>[
        if (item.command != null) _CommandHeader(item: item),
        if (item.changes.isNotEmpty) _FileChanges(changes: item.changes),
        if (item.query != null || item.url != null)
          _Fact(label: item.query ?? item.url!),
        if (item.imagePath != null) _Fact(label: item.imagePath!),
        if (item.input != null) _Payload(label: 'Input', value: item.input),
        if (item.output.trim().isNotEmpty) _Block(text: item.output),
        if (item.result != null) _Payload(label: 'Result', value: item.result),
        if ((item.detail ?? '').trim().isNotEmpty && item.command == null)
          AgentChatMarkdown(text: item.detail!),
        if (item.isPartialContinuation) const AgentChatPartialMessageNote(),
      ],
      if (agentChatItemHasFullData(item)) AgentChatItemFullData(item: item),
    ];
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space8,
      children: sections,
    );
  }

  Widget _reasoning(AgentChatItem item) {
    final text = item.reasoningText.trim().isNotEmpty
        ? item.reasoningText
        : item.text;
    if (item.isPartialContinuation) return AgentChatPartialText(text: text);
    return text.trim().isEmpty
        ? const SizedBox.shrink()
        : AgentChatMarkdown(text: text);
  }
}

class const _CommandHeader({required final AgentChatItem item})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final exitCode = item.exitCode;
    final faint = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundFaint);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space4,
      children: <Widget>[
        _Block(text: '\$ ${item.command}'),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space4,
          crossAxisAlignment: .center,
          children: <Widget>[
            if (exitCode != null)
              AleraBadge(
                label: 'Exit $exitCode',
                tone: exitCode == 0 ? .success : .error,
              ),
            if (item.durationMs case final int duration)
              Text(
                agentChatDurationLabel(Duration(milliseconds: duration)),
                style: faint,
              ),
            if (item.cwd case final String cwd)
              Text(cwd, style: faint, overflow: .ellipsis),
          ],
        ),
      ],
    );
  }
}

class const _FileChanges({required final List<AgentChatFileChange> changes})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      for (final change in changes) _FileChangeRow(change: change),
    ],
  );
}

class const _FileChangeRow({required final AgentChatFileChange change})
    extends StatefulWidget {
  @override
  State<_FileChangeRow> createState() => _FileChangeRowState();
}

class _FileChangeRowState extends State<_FileChangeRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final change = widget.change;
    final counts = change.lineCounts;
    final diff = change.diff;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          onTap: diff == null
              ? null
              : () => setState(() => _expanded = !_expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AleraTokens.minTapTarget,
            ),
            child: Row(
              children: <Widget>[
                AleraBadge(label: _kindLetter(change.kind)),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    change.path,
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foreground,
                    ),
                    overflow: .ellipsis,
                  ),
                ),
                if (counts.additions > 0)
                  Text(
                    '+${counts.additions} ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.success,
                    ),
                  ),
                if (counts.deletions > 0)
                  Text(
                    '-${counts.deletions}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && diff != null) _DiffBlock(diff: diff),
      ],
    );
  }
}

String _kindLetter(AgentChatFileChangeKind kind) => switch (kind) {
  AgentChatFileChangeKind.add => 'A',
  AgentChatFileChangeKind.delete => 'D',
  AgentChatFileChangeKind.rename => 'R',
  AgentChatFileChangeKind.update => 'M',
};

class const _DiffBlock({required final String diff}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = _tail(diff);
    return _Frame(
      child: Text.rich(
        TextSpan(
          children: <TextSpan>[
            for (final line in text.split('\n'))
              TextSpan(
                text: '$line\n',
                style: AleraTokens.monoStyle.copyWith(
                  color: line.startsWith('+') && !line.startsWith('+++')
                      ? AleraTokens.success
                      : line.startsWith('-') && !line.startsWith('---')
                      ? AleraTokens.error
                      : AleraTokens.foregroundMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class const _Payload({
  required final String label,
  required final Object? value,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    spacing: AleraTokens.space4,
    children: <Widget>[
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
      _Block(text: _pretty(value)),
    ],
  );
}

class const _Fact({required final String label}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground),
  );
}

class const _Block({required final String text}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _Frame(
    child: SelectableText(
      _tail(text),
      style: AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground),
    ),
  );
}

/// Code scrolls sideways rather than wrapping, like the Markdown code blocks.
class const _Frame({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.bg,
      border: Border.all(color: AleraTokens.borderSubtle),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: SingleChildScrollView(
      scrollDirection: .horizontal,
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: child,
    ),
  );
}

String _tail(String text) => text.length <= _maxDetailCharacters
    ? text
    : '…${text.substring(text.length - _maxDetailCharacters)}';

String _pretty(Object? value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}
