import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
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
    required this.controller,
  });

  final SessionState state;
  final SessionController controller;

  @override
  State<SessionWorkspaceView> createState() => _SessionWorkspaceViewState();
}

class _SessionWorkspaceViewState extends State<SessionWorkspaceView> {
  final _inputController = TextEditingController();
  bool _rawLogExpanded = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(child: _ChatTimelineList(state: widget.state)),
        _Composer(
          controller: _inputController,
          enabled: widget.state.activeSession != null && !widget.state.isBusy,
          canChangeModel: widget.state.activeSession != null,
          isBusy: widget.state.isBusy,
          activeModelId: widget.state.activeModelId,
          availableModels: widget.state.availableModels,
          onModelChanged: widget.controller.updateActiveSessionModel,
          onSend: _sendInput,
          rawLogExpanded: _rawLogExpanded,
          onToggleRawLog: () =>
              setState(() => _rawLogExpanded = !_rawLogExpanded),
        ),
        _RawLog(state: widget.state, expanded: _rawLogExpanded),
      ],
    );
  }

  void _sendInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _inputController.clear();
    widget.controller.sendInput(text);
  }
}

class _ChatTimelineList extends StatelessWidget {
  const _ChatTimelineList({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageById = <String, TimelineMessage>{
      for (final message in state.timelineMessages) message.id: message,
    };
    final activityById = <String, TimelineActivityItem>{
      for (final activity in state.timelineActivities) activity.id: activity,
    };

    if (state.turnGroups.isEmpty && state.timelineMessages.isEmpty) {
      final session = state.activeSession;
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

    if (state.turnGroups.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space16,
          vertical: AleraTokens.space16,
        ),
        children: state.timelineMessages
            .map((message) => _MessageBubble(message: message))
            .toList(growable: false),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: AleraTokens.space16,
      ),
      itemCount: state.turnGroups.length,
      itemBuilder: (context, index) {
        final group = state.turnGroups[index];
        final userMessage = group.userMessageId == null
            ? null
            : messageById[group.userMessageId!];
        final assistantMessage = group.assistantMessageId == null
            ? null
            : messageById[group.assistantMessageId!];
        final activities = group.activityItemIds
            .map((id) => activityById[id])
            .whereType<TimelineActivityItem>()
            .toList(growable: false);

        return Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (userMessage != null) _MessageBubble(message: userMessage),
              if (assistantMessage != null)
                _MessageBubble(message: assistantMessage),
              if (activities.isNotEmpty)
                _TurnActivityPanel(
                  activities: activities,
                  isTurnRunning:
                      assistantMessage?.isStreaming ??
                      state.activeTurnId == group.turnId,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TimelineMessage message;

  bool get _isUser => message.role == TimelineRole.user;

  @override
  Widget build(BuildContext context) {
    final align = _isUser ? Alignment.centerRight : Alignment.centerLeft;
    final maxWidth = _isUser ? 760.0 : 920.0;
    final background = _isUser
        ? AleraTokens.accentSubtle
        : AleraTokens.surfaceVariant;
    final borderColor = _isUser ? AleraTokens.accent : AleraTokens.borderSubtle;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: EdgeInsets.only(
            top: AleraTokens.space6,
            bottom: AleraTokens.space4,
            left: _isUser ? 80 : 0,
            right: _isUser ? 0 : 80,
          ),
          padding: const EdgeInsets.all(AleraTokens.space12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isUser ? 'you' : 'assistant',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _isUser
                      ? AleraTokens.accent
                      : AleraTokens.foregroundFaint,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
              if (_isUser)
                SelectableText(
                  message.markdownText,
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                _AssistantBubbleMarkdown(
                  markdownText: message.markdownText,
                  isStreaming: message.isStreaming,
                ),
            ],
          ),
        ),
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

    final visibleText = markdownText.trim().isEmpty
        ? (isStreaming ? '_thinking..._' : '_no content_')
        : markdownText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MarkdownBody(
          data: visibleText,
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

class _TurnActivityPanel extends StatefulWidget {
  const _TurnActivityPanel({
    required this.activities,
    required this.isTurnRunning,
  });

  final List<TimelineActivityItem> activities;
  final bool isTurnRunning;

  @override
  State<_TurnActivityPanel> createState() => _TurnActivityPanelState();
}

class _TurnActivityPanelState extends State<_TurnActivityPanel> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final commandCount = widget.activities
        .where((item) => item.kind == ActivityKind.commandExecution)
        .length;
    final fileChangeCount = widget.activities
        .where((item) => item.kind == ActivityKind.fileChange)
        .length;
    final toolCount = widget.activities.length - commandCount - fileChangeCount;

    return Container(
      margin: const EdgeInsets.only(
        top: AleraTokens.space4,
        left: 80,
        right: 80,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Text(
                    'activity',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  _CounterChip(label: '$commandCount cmd'),
                  _CounterChip(label: '$fileChangeCount files'),
                  _CounterChip(label: '$toolCount tools'),
                  if (widget.isTurnRunning)
                    const Padding(
                      padding: EdgeInsets.only(left: AleraTokens.space8),
                      child: SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AleraTokens.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: widget.activities
                  .map((item) => _ActivityItemTile(item: item))
                  .toList(growable: false),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AleraTokens.durationMid,
          ),
        ],
      ),
    );
  }
}

class _CounterChip extends StatelessWidget {
  const _CounterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: AleraTokens.space6),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AleraTokens.foregroundMuted,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _ActivityItemTile extends StatefulWidget {
  const _ActivityItemTile({required this.item});

  final TimelineActivityItem item;

  @override
  State<_ActivityItemTile> createState() => _ActivityItemTileState();
}

class _ActivityItemTileState extends State<_ActivityItemTile> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (widget.item.status) {
      TimelineActivityStatus.inProgress => AleraTokens.accent,
      TimelineActivityStatus.completed => AleraTokens.success,
      TimelineActivityStatus.failed => AleraTokens.error,
      TimelineActivityStatus.declined => AleraTokens.warning,
    };

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.all(AleraTokens.space8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.item.title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AleraTokens.foreground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((widget.item.summary?.isNotEmpty ?? false))
                          Text(
                            widget.item.summary!,
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: AleraTokens.foregroundMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space8,
                0,
                AleraTokens.space8,
                AleraTokens.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if ((widget.item.subtitle?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: AleraTokens.space6,
                      ),
                      child: Text(
                        widget.item.subtitle!,
                        style: AleraTokens.monoStyle.copyWith(fontSize: 11),
                      ),
                    ),
                  if ((widget.item.details?.isNotEmpty ?? false))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AleraTokens.space8),
                      decoration: BoxDecoration(
                        color: AleraTokens.bg,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                        border: Border.all(color: AleraTokens.borderSubtle),
                      ),
                      child: SelectableText(
                        _prettyDetails(widget.item.details!),
                        style: AleraTokens.monoStyle.copyWith(
                          color: AleraTokens.foreground,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.canChangeModel,
    required this.isBusy,
    required this.activeModelId,
    required this.availableModels,
    required this.onModelChanged,
    required this.onSend,
    required this.rawLogExpanded,
    required this.onToggleRawLog,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool canChangeModel;
  final bool isBusy;
  final String activeModelId;
  final List<CodexModelOption> availableModels;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onSend;
  final bool rawLogExpanded;
  final VoidCallback onToggleRawLog;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: <Widget>[
          if (isBusy)
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Tooltip(
                message: rawLogExpanded ? 'hide raw log' : 'show raw log',
                child: IconButton(
                  onPressed: onToggleRawLog,
                  mouseCursor: SystemMouseCursors.click,
                  icon: Icon(
                    Icons.terminal,
                    size: 18,
                    color: rawLogExpanded
                        ? AleraTokens.accent
                        : AleraTokens.foregroundFaint,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        onSend,
                  },
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'send message (⌘+Enter)',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AleraTokens.space12,
                        vertical: AleraTokens.space8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusMd,
                        ),
                        borderSide: const BorderSide(color: AleraTokens.border),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              IconButton(
                onPressed: enabled ? onSend : null,
                mouseCursor: SystemMouseCursors.click,
                style: IconButton.styleFrom(
                  backgroundColor: enabled
                      ? AleraTokens.accent
                      : AleraTokens.surfaceVariant,
                  foregroundColor: enabled
                      ? AleraTokens.onAccent
                      : AleraTokens.foregroundFaint,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  ),
                ),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              Text('model', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: AleraTokens.space8),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: activeModelId,
                  items: availableModels
                      .map(
                        (model) => DropdownMenuItem<String>(
                          value: model.id,
                          child: Text(model.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: canChangeModel
                      ? (value) {
                          if (value != null) {
                            onModelChanged(value);
                          }
                        }
                      : null,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AleraTokens.space8,
                      vertical: AleraTokens.space8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
