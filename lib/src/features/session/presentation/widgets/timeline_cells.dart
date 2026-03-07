import 'dart:convert';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/presentation/widgets/image_zoom_dialog.dart';
import 'package:alera/src/features/session/presentation/widgets/markdown_helpers.dart';
import 'package:alera/src/features/session/presentation/widgets/status_color.dart';
import 'package:flutter/material.dart';

class TimelineCellView extends StatelessWidget {
  const TimelineCellView({
    super.key,
    required this.cell,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final TimelineCell cell;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  Widget build(BuildContext context) {
    return switch (cell.kind) {
      TimelineCellKind.userMessage => UserMessageCell(
        cell: cell,
        markdownEnabled: markdownEnabled,
        onMarkdownModeChanged: onMarkdownModeChanged,
      ),
      TimelineCellKind.assistantMessage => AssistantMessageCell(
        cell: cell,
        markdownEnabled: markdownEnabled,
        onMarkdownModeChanged: onMarkdownModeChanged,
      ),
      TimelineCellKind.progressText => ProgressTextRow(
        cell: cell,
        markdownEnabled: markdownEnabled,
      ),
      TimelineCellKind.reasoning => ReasoningCell(
        key: ValueKey(cell.id),
        cell: cell,
        markdownEnabled: markdownEnabled,
      ),
      TimelineCellKind.toolCall => ToolCallCell(
        key: ValueKey(cell.id),
        cell: cell,
      ),
      TimelineCellKind.plan => PlanCell(
        key: ValueKey(cell.id),
        cell: cell,
        markdownEnabled: markdownEnabled,
      ),
      TimelineCellKind.turnSeparator => const SizedBox.shrink(),
      TimelineCellKind.systemNotice => SystemNoticeCell(cell: cell),
    };
  }
}

class UserMessageCell extends StatefulWidget {
  const UserMessageCell({
    super.key,
    required this.cell,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final TimelineCell cell;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  State<UserMessageCell> createState() => _UserMessageCellState();
}

class _UserMessageCellState extends State<UserMessageCell> {
  bool _isHovered = false;

  List<Map<String, dynamic>> _parseAttachments() {
    final raw = widget.cell.metadata['attachments'];
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    final list = raw.whereType<Map<String, dynamic>>().toList();
    // Sort: files first, images second.
    list.sort((a, b) {
      final aIsImage = a['kind']?.toString() == AttachmentKind.image.name
          ? 1
          : 0;
      final bIsImage = b['kind']?.toString() == AttachmentKind.image.name
          ? 1
          : 0;
      return aIsImage.compareTo(bIsImage);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final messageText = widget.cell.markdownText ?? '';
    final showCopy = _isHovered || !mouseIsConnected();
    final attachments = _parseAttachments();
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.only(
            top: AleraTokens.space6,
            bottom: AleraTokens.space4,
            left: 80,
          ),
          child: MouseRegion(
            key: ValueKey<String>('copy-zone-user-${widget.cell.id}'),
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AleraTokens.space6,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: AleraTokens.space6,
                            runSpacing: AleraTokens.space6,
                            children: attachments
                                .map((att) {
                                  final kind = att['kind']?.toString();
                                  final path = att['path']?.toString() ?? '';
                                  final displayName =
                                      att['displayName']?.toString() ?? path;
                                  if (kind == AttachmentKind.image.name) {
                                    return _AttachmentThumbnail(
                                      path: path,
                                      displayName: displayName,
                                    );
                                  }
                                  return _AttachmentChip(
                                    displayName: displayName,
                                  );
                                })
                                .toList(growable: false),
                          ),
                        ),
                      if (messageText.trim().isNotEmpty)
                        Container(
                          key: ValueKey<String>(
                            'user-bubble-${widget.cell.id}',
                          ),
                          padding: const EdgeInsets.all(AleraTokens.space12),
                          decoration: BoxDecoration(
                            color: AleraTokens.accentSubtle,
                            borderRadius: BorderRadius.circular(
                              AleraTokens.radiusLg,
                            ),
                          ),
                          child: UserBubbleContent(
                            markdownText: messageText,
                            markdownEnabled: widget.markdownEnabled,
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !showCopy,
                    child: AnimatedOpacity(
                      duration: AleraTokens.durationFast,
                      opacity: showCopy ? 1 : 0,
                      child: MessageActionButtons(
                        alignLeft: false,
                        copyKey: ValueKey<String>(
                          'copy-user-${widget.cell.id}',
                        ),
                        copyText: messageText,
                        copiedLabel: 'Message copied',
                        toggleKey: ValueKey<String>(
                          'toggle-markdown-user-${widget.cell.id}',
                        ),
                        markdownEnabled: widget.markdownEnabled,
                        onToggleMarkdown: widget.onMarkdownModeChanged,
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

class AssistantMessageCell extends StatefulWidget {
  const AssistantMessageCell({
    super.key,
    required this.cell,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final TimelineCell cell;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  State<AssistantMessageCell> createState() => _AssistantMessageCellState();
}

class _AssistantMessageCellState extends State<AssistantMessageCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final rawText = widget.cell.markdownText ?? '';
    if (rawText.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final showCopy = _isHovered || !mouseIsConnected();
    return Padding(
      padding: const EdgeInsets.only(
        top: AleraTokens.space6,
        bottom: AleraTokens.space4,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: MouseRegion(
            key: ValueKey<String>('copy-zone-assistant-${widget.cell.id}'),
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Container(
                    key: ValueKey<String>('assistant-bubble-${widget.cell.id}'),
                    child: AssistantBubbleMarkdown(
                      markdownText: rawText,
                      isStreaming: widget.cell.isStreaming,
                      markdownEnabled: widget.markdownEnabled,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !showCopy,
                    child: AnimatedOpacity(
                      duration: AleraTokens.durationFast,
                      opacity: showCopy ? 1 : 0,
                      child: MessageActionButtons(
                        alignLeft: true,
                        copyKey: ValueKey<String>(
                          'copy-assistant-${widget.cell.id}',
                        ),
                        copyText: rawText,
                        copiedLabel: 'Message copied',
                        toggleKey: ValueKey<String>(
                          'toggle-markdown-assistant-${widget.cell.id}',
                        ),
                        markdownEnabled: widget.markdownEnabled,
                        onToggleMarkdown: widget.onMarkdownModeChanged,
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

class AssistantBubbleMarkdown extends StatelessWidget {
  const AssistantBubbleMarkdown({
    super.key,
    required this.markdownText,
    required this.isStreaming,
    required this.markdownEnabled,
  });

  final String markdownText;
  final bool isStreaming;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final messageStyle = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        buildMarkdownContent(
          context: context,
          text: markdownText,
          markdownEnabled: markdownEnabled,
          textStyle: messageStyle,
          markdownStyle: messageStyle,
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
                  'Streaming...',
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

class UserBubbleContent extends StatelessWidget {
  const UserBubbleContent({
    super.key,
    required this.markdownText,
    required this.markdownEnabled,
  });

  final String markdownText;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final messageStyle = Theme.of(context).textTheme.bodyMedium;
    return buildMarkdownContent(
      context: context,
      text: markdownText,
      markdownEnabled: markdownEnabled,
      textStyle: messageStyle,
      markdownStyle: messageStyle,
      useStreaming: false,
    );
  }
}

class ProgressTextRow extends StatelessWidget {
  const ProgressTextRow({
    super.key,
    required this.cell,
    required this.markdownEnabled,
  });

  final TimelineCell cell;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final text = (cell.markdownText ?? '').trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final progressStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foregroundMuted);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final width = maxWidth.isFinite
            ? (maxWidth < 760 ? maxWidth : 760.0)
            : 760.0;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space2,
              ),
              child: buildMarkdownContent(
                context: context,
                text: text,
                markdownEnabled: markdownEnabled,
                textStyle: progressStyle,
                markdownStyle: progressStyle,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ReasoningCell extends StatefulWidget {
  const ReasoningCell({
    super.key,
    required this.cell,
    required this.markdownEnabled,
  });

  final TimelineCell cell;
  final bool markdownEnabled;

  @override
  State<ReasoningCell> createState() => _ReasoningCellState();
}

class _ReasoningCellState extends State<ReasoningCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant ReasoningCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.cell.markdownText ?? '';
    final thinkingColor = AleraTokens.foregroundMuted;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _isHovered
                    ? AleraTokens.surfaceVariant
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
              child: InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space6,
                    vertical: AleraTokens.space4,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.psychology, size: 10, color: thinkingColor),
                      const SizedBox(width: AleraTokens.space6),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                widget.cell.title ?? 'Thinking',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: thinkingColor),
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
              child: buildMarkdownContent(
                context: context,
                text: text,
                markdownEnabled: widget.markdownEnabled,
                textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
                markdownStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ToolCallCell extends StatefulWidget {
  const ToolCallCell({super.key, required this.cell});

  final TimelineCell cell;

  @override
  State<ToolCallCell> createState() => _ToolCallCellState();
}

class _ToolCallCellState extends State<ToolCallCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant ToolCallCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.cell.detailsText ?? '';
    final cellStatusColor = statusColor(widget.cell.status);
    final title = widget.cell.title ?? 'Tool call';
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
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _isHovered
                    ? AleraTokens.surfaceVariant
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
              child: InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space6,
                    vertical: AleraTokens.space4,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 10,
                        child: Center(
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cellStatusColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space6),
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
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
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

class PlanCell extends StatefulWidget {
  const PlanCell({
    super.key,
    required this.cell,
    required this.markdownEnabled,
  });

  final TimelineCell cell;
  final bool markdownEnabled;

  @override
  State<PlanCell> createState() => _PlanCellState();
}

class _PlanCellState extends State<PlanCell> {
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant PlanCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.cell.markdownText ?? '';
    final copyText = widget.cell.detailsText ?? text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Container(
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => setState(() => _collapsed = !_collapsed),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: _collapsed
                  ? BorderRadius.circular(AleraTokens.radiusLg)
                  : const BorderRadius.only(
                      topLeft: Radius.circular(AleraTokens.radiusLg),
                      topRight: Radius.circular(AleraTokens.radiusLg),
                    ),
              splashFactory: NoSplash.splashFactory,
              hoverColor: AleraTokens.surfaceElevated,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                  vertical: AleraTokens.space8,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AleraTokens.space6,
                        vertical: AleraTokens.space2,
                      ),
                      decoration: BoxDecoration(
                        color: AleraTokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                      ),
                      child: Text(
                        'Plan',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    MessageCopyButton(
                      copyText: copyText,
                      copiedLabel: 'Plan copied',
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    Tooltip(
                      message: _collapsed ? 'Expand plan' : 'Collapse plan',
                      child: InkWell(
                        onTap: () => setState(() => _collapsed = !_collapsed),
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                        splashFactory: NoSplash.splashFactory,
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AleraTokens.space4,
                            vertical: AleraTokens.space2,
                          ),
                          child: Icon(
                            _collapsed
                                ? Icons.keyboard_arrow_right
                                : Icons.keyboard_arrow_down,
                            size: 14,
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_collapsed && text.trim().isNotEmpty) ...<Widget>[
              Divider(height: 1, thickness: 1, color: AleraTokens.border),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: _buildBody(context, text),
              ),
              Divider(height: 1, thickness: 1, color: AleraTokens.border),
              Tooltip(
                message: 'Collapse plan',
                child: InkWell(
                  onTap: () => setState(() => _collapsed = true),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AleraTokens.radiusLg),
                    bottomRight: Radius.circular(AleraTokens.radiusLg),
                  ),
                  splashFactory: NoSplash.splashFactory,
                  hoverColor: AleraTokens.surfaceElevated,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AleraTokens.space6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.keyboard_arrow_up,
                          size: 14,
                          color: AleraTokens.foregroundFaint,
                        ),
                        const SizedBox(width: AleraTokens.space4),
                        Text(
                          'Collapse plan',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AleraTokens.foregroundFaint),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String text) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    return buildMarkdownContent(
      context: context,
      text: text,
      markdownEnabled: widget.markdownEnabled,
      textStyle: bodyStyle,
      markdownStyle: bodyStyle,
    );
  }
}

class SystemNoticeCell extends StatelessWidget {
  const SystemNoticeCell({super.key, required this.cell});

  final TimelineCell cell;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Text(
        cell.markdownText ?? cell.title ?? 'System event',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundFaint),
      ),
    );
  }
}

class ExploringClusterCell extends StatefulWidget {
  const ExploringClusterCell({super.key, required this.cells});

  final List<TimelineCell> cells;

  @override
  State<ExploringClusterCell> createState() => _ExploringClusterCellState();
}

class _ExploringClusterCellState extends State<ExploringClusterCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = true;
  }

  @override
  Widget build(BuildContext context) {
    final summary = exploredSummary(widget.cells);
    final isStreaming = widget.cells.any(
      (cell) =>
          cell.status == TimelineCellStatus.inProgress || cell.isStreaming,
    );
    final label = isStreaming
        ? 'Exploring'
        : summary == null
        ? 'Explored'
        : 'Explored $summary';
    final status = widget.cells.last.status;
    final cellStatusColor = statusColor(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: AleraTokens.durationFast,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _isHovered
                  ? AleraTokens.surfaceVariant
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: InkWell(
              onTap: () => setState(() => _collapsed = !_collapsed),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              splashFactory: NoSplash.splashFactory,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 10,
                      child: Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cellStatusColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              label,
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
        ),
        if (!_collapsed)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space4),
            child: Column(
              children: <Widget>[
                for (final cell in widget.cells)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                    child: ToolCallCell(
                      key: ValueKey('cluster-item-${cell.id}'),
                      cell: cell,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String? exploredSummary(List<TimelineCell> cells) {
  var fileCount = 0;
  var searchCount = 0;
  for (final cell in cells) {
    final bucket = cell.metadata['exploreBucket']?.toString().toLowerCase();
    if (bucket == 'search') {
      searchCount += 1;
      continue;
    }
    if (bucket == 'file') {
      fileCount += 1;
    }
  }
  final parts = <String>[];
  if (fileCount > 0) {
    parts.add('$fileCount ${fileCount == 1 ? 'file' : 'files'}');
  }
  if (searchCount > 0) {
    parts.add('$searchCount ${searchCount == 1 ? 'search' : 'searches'}');
  }
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(', ');
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 12,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space4),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 11,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({required this.path, required this.displayName});

  final String path;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return _AttachmentChip(displayName: displayName);
    }
    return GestureDetector(
      onTap: () => showImageZoomDialog(context, path),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          child: Image.file(
            file,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _AttachmentChip(displayName: displayName),
          ),
        ),
      ),
    );
  }
}

bool isExploratoryToolCell(TimelineCell cell) {
  if (cell.kind != TimelineCellKind.toolCall) {
    return false;
  }
  final flag = cell.metadata['isExploratory'];
  if (flag is bool) {
    return flag;
  }
  if (flag is String) {
    final value = flag.toLowerCase().trim();
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
  }
  final bucket = cell.metadata['exploreBucket']?.toString().toLowerCase();
  if (bucket == 'file' || bucket == 'search') {
    return true;
  }
  final title = (cell.title ?? '').toLowerCase();
  return title.startsWith('read') ||
      title.startsWith('list') ||
      title.startsWith('search');
}
