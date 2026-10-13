import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_attachment_bar.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AgentChatSendCallback = bool Function(
  String text,
  List<AgentChatAttachment> attachments,
);

Future<List<String>> _pickFiles() async => <String>[
  for (final file in await openFiles())
    if (file.path.isNotEmpty) file.path,
];

/// The message box under a chat. Enter sends (or queues behind a running
/// turn), Shift+Enter breaks the line, Escape stops a running turn, and the
/// arrow keys recall earlier prompts from an empty box.
class const AgentChatComposer({
  super.key,
  required final TerminalComposerController controller,
  required final String workspaceId,
  required final String chatId,
  required final AgentChatComposerSettings? settings,
  required final AgentChatUsage usage,
  required final bool canSend,
  required final bool busy,
  required final bool canInterrupt,
  required final bool interrupting,
  required final String hintText,
  required final List<String> Function() promptHistory,
  required final AgentChatSendCallback onSend,
  required final VoidCallback onInterrupt,
  required final ValueChanged<AgentChatConfiguration> onConfigure,
  required final ValueChanged<String> onOpenFile,
  final TerminalClipboard clipboard = const NativeTerminalClipboard(),
  final Future<List<String>> Function() pickFiles = _pickFiles,
}) extends StatefulWidget {
  @override
  State<AgentChatComposer> createState() => _AgentChatComposerState();
}

class _AgentChatComposerState extends State<AgentChatComposer> {
  int? _historyIndex;
  String _historyDraft = '';

  TerminalComposerController get _composer => widget.controller;

  @override
  void initState() {
    super.initState();
    _composer.focusNode.onKeyEvent = _handleKey;
  }

  @override
  void didUpdateWidget(covariant AgentChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.controller.focusNode.onKeyEvent == _handleKey) {
        oldWidget.controller.focusNode.onKeyEvent = null;
      }
      widget.controller.focusNode.onKeyEvent = _handleKey;
      _historyIndex = null;
    }
  }

  @override
  void dispose() {
    if (_composer.focusNode.onKeyEvent == _handleKey) {
      _composer.focusNode.onKeyEvent = null;
    }
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final history = widget.promptHistory();
    final text = _composer.textController.text;
    final browsing = _historyIndex != null;
    if (history.isEmpty || (!browsing && text.isNotEmpty)) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final next = browsing ? _historyIndex! - 1 : history.length - 1;
      if (next < 0) return KeyEventResult.handled;
      if (!browsing) _historyDraft = text;
      _recall(next, history[next]);
      return KeyEventResult.handled;
    }
    if (!browsing) return KeyEventResult.ignored;
    final next = _historyIndex! + 1;
    if (next >= history.length) {
      _historyIndex = null;
      _setText(_historyDraft);
    } else {
      _recall(next, history[next]);
    }
    return KeyEventResult.handled;
  }

  void _recall(int index, String text) {
    _historyIndex = index;
    _setText(text);
  }

  void _setText(String text) {
    _composer.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _send() {
    final attachments = <AgentChatAttachment>[
      for (final attachment in _composer.attachments)
        AgentChatAttachment(
          type: attachment.kind == TerminalComposerAttachmentKind.image
              ? AgentChatAttachmentType.localImage
              : AgentChatAttachmentType.file,
          path: attachment.path,
          name: attachment.displayName,
        ),
    ];
    final text = _composer.textController.text;
    if (!widget.onSend(text, attachments)) return;
    _historyIndex = null;
    _composer.textController.clear();
    _composer.removeAttachments(
      _composer.attachments.map((attachment) => attachment.id).toList(),
    );
    _composer.focusNode.requestFocus();
  }

  void _escape() {
    if (widget.canInterrupt) {
      widget.onInterrupt();
    } else {
      _composer.focusNode.unfocus();
    }
  }

  Future<void> _addFiles() async {
    try {
      final paths = await widget.pickFiles();
      if (!mounted || paths.isEmpty) return;
      _composer.addPathAttachments(paths);
      _composer.focusNode.requestFocus();
    } on Object catch (error) {
      AleraToast.publish(message: 'Could not add files: $error', tone: .error);
    }
  }

  Future<bool> _paste() async {
    try {
      final paths = await widget.clipboard.readFilePaths();
      if (paths.isNotEmpty) {
        _composer.addPathAttachments(paths);
        return true;
      }
    } on Object {
      // Text and image formats are still worth trying.
    }
    try {
      final text = await widget.clipboard.readText();
      if (text != null && text.isNotEmpty) return false;
    } on Object {
      // Image-only clipboards can reject text reads on some platforms.
    }
    try {
      final imagePath = await widget.clipboard.saveImageAsTempFile();
      if (imagePath == null || imagePath.isEmpty) return false;
      _composer.addPathAttachment(
        imagePath,
        kind: TerminalComposerAttachmentKind.image,
      );
      return true;
    } on Object {
      AleraToast.publish(
        message: 'Could not paste clipboard image.',
        tone: .error,
      );
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textActions = AleraTextActionsScope.maybeOf(context);
    final settings = widget.settings;
    return DragTarget<TerminalPathDragPayload>(
      onWillAcceptWithDetails: (_) => widget.canSend,
      onAcceptWithDetails: (details) {
        _composer.addPathAttachments(details.data.paths);
        _composer.focusNode.requestFocus();
      },
      builder: (context, _, _) => AiDictationTarget(
        controller: _composer.textController,
        focusNode: _composer.focusNode,
        workspaceId: widget.workspaceId,
        tabId: widget.chatId,
        initialPrompt: 'The user is chatting with a coding agent.',
        builder: (context, targetId) => ListenableBuilder(
          // The send button follows the text as well as the attachments.
          listenable: Listenable.merge(<Listenable>[
            _composer,
            _composer.textController,
          ]),
          builder: (context, _) => AleraComposer(
            controller: _composer.textController,
            focusNode: _composer.focusNode,
            enabled: widget.canSend,
            hasAttachments: _composer.attachments.isNotEmpty,
            hintText: widget.hintText,
            attachmentBar: TerminalComposerAttachmentBar(
              attachments: _composer.attachments,
              onRemove: _composer.removeAttachment,
              onOpenFile: widget.onOpenFile,
              enabled: widget.canSend,
            ),
            textActions: textActions?.enabled == true
                ? textActions!.actions
                : const [],
            onTextActionSelected: (actionId) {
              final editable = _composer.focusNode.context
                  ?.findAncestorStateOfType<EditableTextState>();
              if (editable != null) textActions?.run(editable, actionId);
            },
            onPaste: _paste,
            onSend: _send,
            onClose: _escape,
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space8,
                0,
                AleraTokens.space8,
                AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  AleraIconButton(
                    key: const ValueKey<String>('agent-chat-attach'),
                    tooltip: 'Add Files',
                    icon: AleraIcons.attach,
                    onPressed: widget.canSend
                        ? () => unawaited(_addFiles())
                        : null,
                  ),
                  Expanded(
                    child: AleraHorizontalScrollView(
                      child: settings == null
                          ? const SizedBox.shrink()
                          : AgentChatComposerControls(
                              settings: settings,
                              enabled: widget.canSend,
                              onConfigure: widget.onConfigure,
                            ),
                    ),
                  ),
                  AgentChatContextUsage(usage: widget.usage),
                  AiDictationControl(
                    key: const ValueKey<String>('agent-chat-dictation'),
                    targetId: targetId,
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  _SendOrStopButton(
                    hasDraft:
                        _composer.textController.text.trim().isNotEmpty ||
                        _composer.attachments.isNotEmpty,
                    canSend: widget.canSend,
                    busy: widget.busy,
                    canInterrupt: widget.canInterrupt,
                    interrupting: widget.interrupting,
                    onSend: _send,
                    onInterrupt: widget.onInterrupt,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _SendOrStopButton({
  required final bool hasDraft,
  required final bool canSend,
  required final bool busy,
  required final bool canInterrupt,
  required final bool interrupting,
  required final VoidCallback onSend,
  required final VoidCallback onInterrupt,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (busy && !hasDraft) {
      return AleraIconButton(
        key: const ValueKey<String>('agent-chat-stop'),
        tooltip: interrupting ? 'Stopping' : 'Stop',
        icon: AleraIcons.stop,
        iconColor: AleraTokens.onAccent,
        backgroundColor: canInterrupt && !interrupting
            ? AleraTokens.accent
            : AleraTokens.surface,
        borderRadius: AleraTokens.radiusPill,
        minSize: AleraTokens.space32,
        onPressed: canInterrupt && !interrupting ? onInterrupt : null,
      );
    }
    final enabled = canSend && hasDraft;
    return AleraIconButton(
      key: const ValueKey<String>('agent-chat-send'),
      tooltip: busy ? 'Queue Message' : 'Send Message',
      icon: AleraIcons.arrowUp,
      iconColor: enabled ? AleraTokens.onAccent : AleraTokens.foregroundFaint,
      backgroundColor: enabled ? AleraTokens.accent : AleraTokens.surface,
      borderRadius: AleraTokens.radiusPill,
      minSize: AleraTokens.space32,
      onPressed: enabled ? onSend : null,
    );
  }
}
