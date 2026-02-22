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
    required this.rawLogExpanded,
    required this.onToggleRawLog,
  });

  final SessionState state;
  final SessionController controller;
  final bool rawLogExpanded;
  final VoidCallback onToggleRawLog;

  @override
  State<SessionWorkspaceView> createState() => _SessionWorkspaceViewState();
}

class _SessionWorkspaceViewState extends State<SessionWorkspaceView> {
  final _inputController = TextEditingController();

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
    if (_isUser) {
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
              message.markdownText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(
        top: AleraTokens.space6,
        bottom: AleraTokens.space4,
      ),
      child: _AssistantBubbleMarkdown(
        markdownText: message.markdownText,
        isStreaming: message.isStreaming,
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
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
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
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        widget.onSend,
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
