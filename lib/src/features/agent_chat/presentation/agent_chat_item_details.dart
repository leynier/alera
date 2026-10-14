import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Long process output only shows its tail; the full text stays on the host.
const int _maxShownOutputLength = 20000;

// A diff renders this many lines until the person asks for the rest, so
// opening a large edit does not lay out thousands of rows at once.
const int _maxShownDiffLines = 200;

// Tool input or result JSON with more values than this is formatted on a
// background isolate instead of during the frame that opens the row.
const int _backgroundFormatNodes = 2000;

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

/// Everything known about one action: the command and its output, the files
/// it changed, the tool's input and result, or the raw provider data.
class const AgentChatItemDetails({
  super.key,
  required final AgentChatItem item,
  required final ValueChanged<String> onOpenFile,
}) extends StatefulWidget {
  @override
  State<AgentChatItemDetails> createState() => _AgentChatItemDetailsState();
}

class _AgentChatItemDetailsState extends State<AgentChatItemDetails> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final label = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final sections = <Widget>[
      if (item.command case final String command)
        _Section(
          label: 'Command',
          child: _MonoBlock(text: command),
        ),
      if (_facts(item) case final String facts when facts.isNotEmpty)
        Text(facts, style: label),
      if (item.changes.isNotEmpty)
        _Section(
          label: item.changes.length == 1 ? 'Changed File' : 'Changed Files',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final change in item.changes)
                _FileChangeView(change: change, onOpenFile: widget.onOpenFile),
            ],
          ),
        ),
      if (item.query case final String query)
        _Section(label: 'Query', child: Text(query)),
      if (item.url case final String url)
        _Section(label: 'Address', child: Text(url)),
      if (item.imagePath case final String path)
        _Section(
          label: 'Image',
          child: _PathLink(path: path, onOpen: widget.onOpenFile),
        ),
      if (item.input != null)
        _Section(
          label: 'Input',
          child: _FormattedBlock(value: item.input),
        ),
      if (item.result != null)
        _Section(
          label: 'Result',
          child: _FormattedBlock(value: item.result),
        ),
      if (item.detail case final String detail
          when detail.trim().isNotEmpty && detail != item.command)
        _Section(label: 'Details', child: Text(detail)),
      if (item.output.trim().isNotEmpty)
        _Section(
          label: 'Output',
          child: _MonoBlock(text: _tail(item.output), scrollable: true),
        ),
      if (item.isPartialContinuation) const AgentChatPartialMessageNote(),
      // The retained payload supersedes the bounded raw data it was cut from.
      if (agentChatItemHasFullData(item))
        AgentChatItemFullData(item: item)
      else if (item.data.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            child: Text(_showRaw ? 'Hide Raw Data' : 'Show Raw Data'),
          ),
        ),
      if (_showRaw && !agentChatItemHasFullData(item))
        _FormattedBlock(value: item.data, scrollable: true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AleraTokens.space8,
      children: sections,
    );
  }

  String _facts(AgentChatItem item) => <String>[
    if (item.cwd case final String cwd) 'In $cwd',
    if (item.exitCode case final int code) 'Exit code $code',
    if (item.durationMs case final int ms)
      'Took ${agentChatDurationLabel(Duration(milliseconds: ms))}',
    if (item.server case final String server) 'Server $server',
    if (item.toolName case final String tool) 'Tool $tool',
  ].join(' · ');
}

String _formatValue(Object? value) {
  if (value is String) return value;
  try {
    return _prettyJson.convert(value);
  } on Object {
    return value.toString();
  }
}

/// How many values [value] holds, counting no further than [limit].
int _nodeCount(Object? value, int limit) {
  var count = 0;
  final pending = <Object?>[value];
  while (pending.isNotEmpty && count <= limit) {
    final next = pending.removeLast();
    count += 1;
    if (next is Map) {
      pending.addAll(next.values);
    } else if (next is Iterable) {
      pending.addAll(next);
    }
  }
  return count;
}

/// Tool JSON, formatted once per value: inline when small, on a background
/// isolate when large, so expanding a row never stalls a frame.
class const _FormattedBlock({
  required final Object? value,
  final bool scrollable = false,
}) extends StatefulWidget {
  @override
  State<_FormattedBlock> createState() => _FormattedBlockState();
}

class _FormattedBlockState extends State<_FormattedBlock> {
  String? _text;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _format();
  }

  @override
  void didUpdateWidget(covariant _FormattedBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) _format();
  }

  void _format() {
    final value = widget.value;
    final generation = ++_generation;
    if (value is String ||
        _nodeCount(value, _backgroundFormatNodes) <= _backgroundFormatNodes) {
      _text = _formatValue(value);
      return;
    }
    _text = null;
    unawaited(
      compute(_formatValue, value).then((text) {
        if (mounted && generation == _generation) setState(() => _text = text);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null) {
      return AleraShimmerText(
        text: 'Formatting',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      );
    }
    return _MonoBlock(text: text, scrollable: widget.scrollable);
  }
}

String _tail(String output) => output.length <= _maxShownOutputLength
    ? output
    : output.substring(output.length - _maxShownOutputLength);

class const _Section({required final String label, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AleraTokens.space4,
    children: <Widget>[
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
      child,
    ],
  );
}

class const _MonoBlock({
  required final String text,
  final bool scrollable = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Not AleraHorizontalScrollView: these blocks sit in the timeline, and
    // the mouse wheel must keep scrolling the conversation.
    final body = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Text(
        text,
        style: AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: scrollable
          ? ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: AleraTokens.agentChatDetailsMaxHeight,
              ),
              child: SingleChildScrollView(reverse: true, child: body),
            )
          : body,
    );
  }
}

class const _PathLink({
  required final String path,
  required final ValueChanged<String> onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onOpen(path),
    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
      child: Row(
        children: <Widget>[
          AleraFileIcon(
            pathOrName: path,
            kind: AleraFileIconKind.file,
            size: AleraTokens.iconMd,
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              path,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.info),
            ),
          ),
        ],
      ),
    ),
  );
}

class const _FileChangeView({
  required final AgentChatFileChange change,
  required final ValueChanged<String> onOpenFile,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counts = change.lineCounts;
    final verb = switch (change.kind) {
      AgentChatFileChangeKind.add => 'Added',
      AgentChatFileChangeKind.delete => 'Deleted',
      AgentChatFileChangeKind.rename => 'Renamed',
      AgentChatFileChangeKind.update => 'Edited',
    };
    final caption = <String>[
      verb,
      if (change.movePath case final String target) 'to $target',
      if (counts.additions > 0 || counts.deletions > 0)
        '+${counts.additions} -${counts.deletions}',
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AleraTokens.space4,
        children: <Widget>[
          _PathLink(path: change.path, onOpen: onOpenFile),
          Text(caption, style: AleraTokens.labelMicroFaintStyle),
          if (change.diff case final String diff when diff.trim().isNotEmpty)
            _DiffBlock(diff: diff),
        ],
      ),
    );
  }
}

class const _DiffBlock({required final String diff}) extends StatefulWidget {
  @override
  State<_DiffBlock> createState() => _DiffBlockState();
}

class _DiffBlockState extends State<_DiffBlock> {
  late List<String> _lines = _tail(widget.diff).split('\n');
  bool _showAll = false;

  @override
  void didUpdateWidget(covariant _DiffBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diff != widget.diff) {
      _lines = _tail(widget.diff).split('\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _showAll ? 0 : _lines.length - _maxShownDiffLines;
    final lines = hidden > 0 ? _lines.take(_maxShownDiffLines) : _lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _diffBody(lines),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text(
                hidden == 1 ? 'Show 1 More Line' : 'Show $hidden More Lines',
              ),
            ),
          ),
      ],
    );
  }

  Widget _diffBody(Iterable<String> lines) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: AleraTokens.agentChatDetailsMaxHeight,
        ),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final line in lines)
                  ColoredBox(
                    color: switch (line) {
                      _ when line.startsWith('+') && !line.startsWith('+++') =>
                        AleraTokens.codexDiffAdditionBackground,
                      _ when line.startsWith('-') && !line.startsWith('---') =>
                        AleraTokens.codexDiffDeletionBackground,
                      _ => Colors.transparent,
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AleraTokens.space8,
                      ),
                      child: Text(
                        line,
                        style: AleraTokens.monoStyle.copyWith(
                          color: line.startsWith('@@')
                              ? AleraTokens.info
                              : AleraTokens.foreground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
