import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class SessionWorkspaceView extends StatefulWidget {
  const SessionWorkspaceView({
    super.key,
    required this.state,
    required this.onSendInput,
    required this.onModelChanged,
    required this.rawLogExpanded,
  });

  final SessionState state;
  final ValueChanged<String> onSendInput;
  final ValueChanged<String> onModelChanged;
  final bool rawLogExpanded;

  @override
  State<SessionWorkspaceView> createState() => _SessionWorkspaceViewState();
}

class _SessionWorkspaceViewState extends State<SessionWorkspaceView> {
  final _inputController = TextEditingController();
  final Set<String> _expandedWorkedTurns = <String>{};

  @override
  void didUpdateWidget(covariant SessionWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.activeSessionId != widget.state.activeSessionId) {
      _expandedWorkedTurns.clear();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: _ChatTimelineList(
            state: widget.state,
            expandedWorkedTurns: _expandedWorkedTurns,
            onToggleWorkedTurn: _toggleWorkedTurn,
          ),
        ),
        _Composer(
          controller: _inputController,
          enabled: widget.state.activeSession != null && !widget.state.isBusy,
          canChangeModel: widget.state.activeSession != null,
          isBusy: widget.state.isBusy,
          activeModelId: widget.state.activeModelId,
          availableModels: widget.state.availableModels,
          onModelChanged: widget.onModelChanged,
          onSend: _sendInput,
        ),
        _RawLog(state: widget.state, expanded: widget.rawLogExpanded),
      ],
    );
  }

  void _sendInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _inputController.clear();
    widget.onSendInput(text);
  }

  void _toggleWorkedTurn(String turnId) {
    setState(() {
      if (_expandedWorkedTurns.contains(turnId)) {
        _expandedWorkedTurns.remove(turnId);
      } else {
        _expandedWorkedTurns.add(turnId);
      }
    });
  }
}

class _ChatTimelineList extends StatelessWidget {
  const _ChatTimelineList({
    required this.state,
    required this.expandedWorkedTurns,
    required this.onToggleWorkedTurn,
  });

  final SessionState state;
  final Set<String> expandedWorkedTurns;
  final ValueChanged<String> onToggleWorkedTurn;

  @override
  Widget build(BuildContext context) {
    if (state.timelineCells.isEmpty) {
      return _EmptyChatState(state: state);
    }

    final timelineWidgets = _buildTimelineWidgets();
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: AleraTokens.space16,
      ),
      children: timelineWidgets,
    );
  }

  List<Widget> _buildTimelineWidgets() {
    final cells = state.timelineCells;
    final separatorsByTurn = <String, TimelineCell>{};
    final firstIndexByTurn = <String, int>{};

    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final turnId = cell.turnId;
      if (turnId != null) {
        firstIndexByTurn.putIfAbsent(turnId, () => i);
        if (cell.kind == TimelineCellKind.turnSeparator) {
          separatorsByTurn[turnId] = cell;
        }
      }
    }

    final renderedCompletedTurns = <String>{};
    final widgets = <Widget>[];

    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final turnId = cell.turnId;
      if (turnId == null) {
        if (cell.kind == TimelineCellKind.turnSeparator) {
          continue;
        }
        widgets.add(_timelineCellWithSpacing(cell));
        continue;
      }

      final separator = separatorsByTurn[turnId];
      final isCompletedTurn = separator != null;
      if (!isCompletedTurn) {
        if (cell.kind == TimelineCellKind.turnSeparator) {
          continue;
        }
        widgets.add(_timelineCellWithSpacing(cell));
        continue;
      }

      final firstTurnIndex = firstIndexByTurn[turnId];
      if (firstTurnIndex != i || renderedCompletedTurns.contains(turnId)) {
        continue;
      }
      renderedCompletedTurns.add(turnId);

      final turnCells = cells
          .where(
            (candidate) =>
                candidate.turnId == turnId &&
                candidate.kind != TimelineCellKind.turnSeparator,
          )
          .toList(growable: false);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _CompletedTurnSection(
            turnId: turnId,
            separator: separator,
            turnCells: turnCells,
            workedExpanded: expandedWorkedTurns.contains(turnId),
            onToggleWorked: () => onToggleWorkedTurn(turnId),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _timelineCellWithSpacing(TimelineCell cell) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: _TimelineCellView(cell: cell),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final session = state.activeSession;
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            session?.title ?? 'session active',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space8),
          if (session != null)
            Text(
              session.workspacePath,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          const SizedBox(height: AleraTokens.space16),
          const Text(
            'start the conversation by sending a message',
            style: TextStyle(color: AleraTokens.foregroundFaint),
          ),
        ],
      ),
    );
  }
}

class _TimelineCellView extends StatelessWidget {
  const _TimelineCellView({required this.cell});

  final TimelineCell cell;

  @override
  Widget build(BuildContext context) {
    return switch (cell.kind) {
      TimelineCellKind.userMessage => _UserMessageCell(cell: cell),
      TimelineCellKind.assistantMessage => _AssistantMessageCell(cell: cell),
      TimelineCellKind.reasoning => _ReasoningCell(
        key: ValueKey(cell.id),
        cell: cell,
      ),
      TimelineCellKind.toolCall => _ToolCallCell(
        key: ValueKey(cell.id),
        cell: cell,
      ),
      TimelineCellKind.turnSeparator => const SizedBox.shrink(),
      TimelineCellKind.systemNotice => _SystemNoticeCell(cell: cell),
    };
  }
}

class _CompletedTurnSection extends StatelessWidget {
  const _CompletedTurnSection({
    required this.turnId,
    required this.separator,
    required this.turnCells,
    required this.workedExpanded,
    required this.onToggleWorked,
  });

  final String turnId;
  final TimelineCell separator;
  final List<TimelineCell> turnCells;
  final bool workedExpanded;
  final VoidCallback onToggleWorked;

  @override
  Widget build(BuildContext context) {
    final users = <TimelineCell>[];
    final assistants = <TimelineCell>[];
    final secondary = <TimelineCell>[];

    for (final cell in turnCells) {
      switch (cell.kind) {
        case TimelineCellKind.userMessage:
          users.add(cell);
        case TimelineCellKind.assistantMessage:
          assistants.add(cell);
        case TimelineCellKind.reasoning ||
            TimelineCellKind.toolCall ||
            TimelineCellKind.systemNotice:
          secondary.add(cell);
        case TimelineCellKind.turnSeparator:
          break;
      }
    }

    final hasSecondary = secondary.isNotEmpty;
    final children = <Widget>[
      for (final userCell in users)
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _TimelineCellView(cell: userCell),
        ),
    ];

    if (hasSecondary) {
      children.add(
        _WorkedForDivider(
          label: _workedForLabel(separator),
          expanded: workedExpanded,
          onTap: onToggleWorked,
        ),
      );
      if (workedExpanded) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: Column(
              children: <Widget>[
                for (final secondaryCell in secondary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                    child: _TimelineCellView(cell: secondaryCell),
                  ),
              ],
            ),
          ),
        );
      }
    }

    if (hasSecondary && workedExpanded) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: AleraTokens.space8),
          child: _FinalMessageDivider(),
        ),
      );
    }
    children.addAll(
      assistants.map(
        (assistantCell) => Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _TimelineCellView(cell: assistantCell),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _WorkedForDivider extends StatelessWidget {
  const _WorkedForDivider({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
        InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Icon(
                  expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 14,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

class _FinalMessageDivider extends StatelessWidget {
  const _FinalMessageDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
          child: Text(
            'Final message',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

String _workedForLabel(TimelineCell separatorCell) {
  final metadata = separatorCell.metadata;
  final formatted = _formatWorkedDuration(metadata);
  if (formatted != null) {
    return 'Worked for $formatted';
  }
  final subtitle = separatorCell.subtitle;
  if (subtitle != null && subtitle.trim().isNotEmpty) {
    final firstSegment = subtitle.split('•').first.trim();
    if (firstSegment.isNotEmpty) {
      return 'Worked for $firstSegment';
    }
  }
  return 'Worked for some time';
}

String? _formatWorkedDuration(Map<String, dynamic> metadata) {
  final durationMs =
      _asNum(metadata['durationMs']) ??
      _asNum(metadata['duration_ms']) ??
      _durationFromTimestamps(metadata);
  if (durationMs == null || durationMs <= 0) {
    return null;
  }
  final totalSeconds = (durationMs / 1000).round();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (seconds == 0) {
    return '${minutes}m';
  }
  return '${minutes}m ${seconds}s';
}

num? _durationFromTimestamps(Map<String, dynamic> metadata) {
  final createdAt =
      _asNum(metadata['createdAt']) ?? _asNum(metadata['created_at']);
  final updatedAt =
      _asNum(metadata['updatedAt']) ?? _asNum(metadata['updated_at']);
  if (createdAt == null || updatedAt == null || updatedAt < createdAt) {
    return null;
  }
  return (updatedAt - createdAt) * 1000;
}

num? _asNum(dynamic value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

class _UserMessageCell extends StatelessWidget {
  const _UserMessageCell({required this.cell});

  final TimelineCell cell;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.only(
            top: AleraTokens.space6,
            bottom: AleraTokens.space4,
            left: 80,
          ),
          padding: const EdgeInsets.all(AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.accentSubtle,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          ),
          child: SelectableText(
            cell.markdownText ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _AssistantMessageCell extends StatelessWidget {
  const _AssistantMessageCell({required this.cell});

  final TimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final visibleText = (cell.markdownText ?? '').trim().isEmpty
        ? (cell.isStreaming ? '_thinking..._' : '_no content_')
        : cell.markdownText!;

    return Padding(
      padding: const EdgeInsets.only(
        top: AleraTokens.space6,
        bottom: AleraTokens.space4,
      ),
      child: _AssistantBubbleMarkdown(
        markdownText: visibleText,
        isStreaming: cell.isStreaming,
      ),
    );
  }
}

class _AssistantBubbleMarkdown extends StatelessWidget {
  const _AssistantBubbleMarkdown({
    required this.markdownText,
    required this.isStreaming,
  });

  final String markdownText;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyMedium,
      code: AleraTokens.monoStyle.copyWith(
        fontSize: 12,
        color: AleraTokens.foreground,
      ),
      codeblockDecoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      blockquoteDecoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MarkdownBody(
          data: markdownText,
          styleSheet: styleSheet,
          builders: <String, MarkdownElementBuilder>{
            'pre': _CodeBlockBuilder(context),
          },
          selectable: true,
        ),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.space6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AleraTokens.accent,
                  ),
                ),
                SizedBox(width: AleraTokens.space6),
                Text(
                  'streaming...',
                  style: TextStyle(
                    color: AleraTokens.foregroundFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReasoningCell extends StatefulWidget {
  const _ReasoningCell({super.key, required this.cell});

  final TimelineCell cell;

  @override
  State<_ReasoningCell> createState() => _ReasoningCellState();
}

class _ReasoningCellState extends State<_ReasoningCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant _ReasoningCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.cell.markdownText ?? '';
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              onTap: () => setState(() => _collapsed = !_collapsed),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              widget.cell.title ?? 'Thinking',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AleraTokens.foregroundMuted,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space4),
                          AnimatedOpacity(
                            duration: AleraTokens.durationFast,
                            opacity: _isHovered ? 1 : 0,
                            child: SizedBox(
                              width: 14,
                              child: Icon(
                                _collapsed
                                    ? Icons.keyboard_arrow_right
                                    : Icons.keyboard_arrow_down,
                                size: 14,
                                color: AleraTokens.foregroundFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.cell.status ==
                        TimelineCellStatus.inProgress) ...<Widget>[
                      const SizedBox(width: AleraTokens.space6),
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!_collapsed && text.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(
                left: AleraTokens.space8,
                top: AleraTokens.space4,
              ),
              padding: const EdgeInsets.only(left: AleraTokens.space8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AleraTokens.borderSubtle, width: 2),
                ),
              ),
              child: MarkdownBody(
                data: text,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                selectable: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolCallCell extends StatefulWidget {
  const _ToolCallCell({super.key, required this.cell});

  final TimelineCell cell;

  @override
  State<_ToolCallCell> createState() => _ToolCallCellState();
}

class _ToolCallCellState extends State<_ToolCallCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant _ToolCallCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.cell.detailsText ?? '';
    final statusColor = _statusColor(widget.cell.status);
    final title = widget.cell.title ?? 'tool call';
    final subtitle = widget.cell.subtitle;
    final rowLabel = (subtitle == null || subtitle.isEmpty)
        ? title
        : '$title · $subtitle';

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              onTap: () => setState(() => _collapsed = !_collapsed),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              rowLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AleraTokens.foregroundMuted,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space4),
                          AnimatedOpacity(
                            duration: AleraTokens.durationFast,
                            opacity: _isHovered ? 1 : 0,
                            child: SizedBox(
                              width: 14,
                              child: Icon(
                                _collapsed
                                    ? Icons.keyboard_arrow_right
                                    : Icons.keyboard_arrow_down,
                                size: 14,
                                color: AleraTokens.foregroundFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_collapsed && details.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(
                left: AleraTokens.space8,
                top: AleraTokens.space4,
              ),
              padding: const EdgeInsets.all(AleraTokens.space8),
              decoration: BoxDecoration(
                color: AleraTokens.surface,
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: SelectableText(
                _prettyDetails(details),
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _prettyDetails(String raw) {
    final trimmed = raw.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }
}

class _SystemNoticeCell extends StatelessWidget {
  const _SystemNoticeCell({required this.cell});

  final TimelineCell cell;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Text(
        cell.markdownText ?? cell.title ?? 'system event',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundFaint),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder(this.context);

  final BuildContext context;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (text.trim().isEmpty) {
      return null;
    }
    return _CopyableCodeBlock(code: text);
  }
}

class _CopyableCodeBlock extends StatelessWidget {
  const _CopyableCodeBlock({required this.code});

  final String code;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('code copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AleraTokens.borderSubtle),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'code',
                    style: TextStyle(
                      color: AleraTokens.foregroundFaint,
                      fontSize: 10,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _copy(context),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AleraTokens.space6,
                      vertical: AleraTokens.space2,
                    ),
                    child: Text(
                      'copy',
                      style: TextStyle(
                        color: AleraTokens.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: SelectableText(
              code,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foreground,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.canChangeModel,
    required this.isBusy,
    required this.activeModelId,
    required this.availableModels,
    required this.onModelChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool canChangeModel;
  final bool isBusy;
  final String activeModelId;
  final List<CodexModelOption> availableModels;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  static const _reasoningOptions = <String, String>{
    'low': 'Low',
    'medium': 'Medium',
    'high': 'High',
    'extra_high': 'Extra High',
  };

  String _reasoningLevel = 'high';

  String get _activeModelLabel {
    for (final model in widget.availableModels) {
      if (model.id == widget.activeModelId) {
        return model.label;
      }
    }
    return widget.activeModelId;
  }

  String get _reasoningLabel => _reasoningOptions[_reasoningLevel] ?? 'High';

  void _sendFromShortcut() {
    if (!widget.enabled) {
      return;
    }
    widget.onSend();
  }

  void _insertLineBreak() {
    if (!widget.enabled) {
      return;
    }
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final nextText = value.text.replaceRange(start, end, '\n');
    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        children: <Widget>[
          if (widget.isBusy)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  color: AleraTokens.accent,
                  backgroundColor: AleraTokens.surfaceVariant,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
              border: Border.all(color: AleraTokens.border),
            ),
            child: Column(
              children: <Widget>[
                CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter):
                        _sendFromShortcut,
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): _insertLineBreak,
                  },
                  child: TextField(
                    controller: widget.controller,
                    enabled: widget.enabled,
                    minLines: 2,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Ask for follow-up changes',
                      filled: true,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.fromLTRB(
                        AleraTokens.space16,
                        AleraTokens.space16,
                        AleraTokens.space16,
                        AleraTokens.space8,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AleraTokens.space8,
                    0,
                    AleraTokens.space8,
                    AleraTokens.space8,
                  ),
                  child: Row(
                    children: <Widget>[
                      InkWell(
                        onTap: () {},
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(AleraTokens.space4),
                          child: Icon(
                            Icons.add,
                            size: 18,
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space4),
                      PopupMenuButton<String>(
                        onSelected: widget.canChangeModel
                            ? widget.onModelChanged
                            : null,
                        enabled: widget.canChangeModel,
                        constraints: const BoxConstraints(minWidth: 220),
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            enabled: false,
                            height: 32,
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Select model',
                              style: TextStyle(
                                color: AleraTokens.foregroundFaint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          ...widget.availableModels.map(
                            (model) => _DropdownEntry(
                              value: model.id,
                              label: model.label,
                              selected: model.id == widget.activeModelId,
                            ),
                          ),
                        ],
                        child: _ComposerChip(label: _activeModelLabel),
                      ),
                      const SizedBox(width: AleraTokens.space6),
                      PopupMenuButton<String>(
                        onSelected: (value) =>
                            setState(() => _reasoningLevel = value),
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            enabled: false,
                            height: 32,
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Select reasoning',
                              style: TextStyle(
                                color: AleraTokens.foregroundFaint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          ..._reasoningOptions.entries.map(
                            (entry) => _DropdownEntry(
                              value: entry.key,
                              label: entry.value,
                              selected: entry.key == _reasoningLevel,
                            ),
                          ),
                        ],
                        child: _ComposerChip(label: _reasoningLabel),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: widget.enabled ? widget.onSend : null,
                        mouseCursor: SystemMouseCursors.click,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: widget.enabled
                              ? AleraTokens.accent
                              : AleraTokens.surface,
                          foregroundColor: widget.enabled
                              ? AleraTokens.onAccent
                              : AleraTokens.foregroundFaint,
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.arrow_upward, size: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerChip extends StatelessWidget {
  const _ComposerChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: AleraTokens.foregroundMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: AleraTokens.space4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AleraTokens.foregroundFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownEntry extends PopupMenuEntry<String> {
  const _DropdownEntry({
    required this.value,
    required this.label,
    this.selected = false,
  });

  final String value;
  final String label;
  final bool selected;

  @override
  double get height => 36;

  @override
  bool represents(String? value) => this.value == value;

  @override
  State<_DropdownEntry> createState() => _DropdownEntryState();
}

class _DropdownEntryState extends State<_DropdownEntry> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space2,
        vertical: 1,
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(widget.value),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space8,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (widget.selected)
                const Icon(
                  Icons.check,
                  size: 16,
                  color: AleraTokens.foreground,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RawLog extends StatelessWidget {
  const _RawLog({required this.state, required this.expanded});

  final SessionState state;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AleraTokens.durationMid,
      curve: Curves.easeOut,
      height: expanded ? 140 : 0,
      decoration: BoxDecoration(
        border: expanded
            ? Border(top: BorderSide(color: Theme.of(context).dividerColor))
            : null,
      ),
      child: expanded
          ? ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space4,
              ),
              itemCount: state.activityLog.length,
              itemBuilder: (context, index) {
                final logIndex = state.activityLog.length - 1 - index;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space2,
                  ),
                  child: Text(
                    state.activityLog[logIndex],
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foregroundFaint,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            )
          : null,
    );
  }
}

Color _statusColor(TimelineCellStatus status) {
  return switch (status) {
    TimelineCellStatus.inProgress => AleraTokens.accent,
    TimelineCellStatus.completed => AleraTokens.success,
    TimelineCellStatus.failed => AleraTokens.error,
    TimelineCellStatus.declined => AleraTokens.warning,
    TimelineCellStatus.info => AleraTokens.foregroundFaint,
  };
}
