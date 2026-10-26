import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_ime_composition_key_guard.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_usage_popover.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_attachment_bar.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AgentChatSendCallback = bool Function(
  String text,
  List<AgentChatAttachment> attachments, {
  bool steer,
});

Future<List<String>> _pickFiles() async => <String>[
  for (final file in await openFiles())
    if (file.path.isNotEmpty) file.path,
];

/// The message box under a chat. Enter sends (or queues behind a running
/// turn), Mod+Enter steers into the running turn when the agent supports it,
/// Shift+Enter breaks the line, Escape stops a running turn, and the arrow
/// keys recall earlier prompts from an empty box until the recalled prompt is
/// edited. [canSend] lets the person write; [canSubmit] lets the message go,
/// so a draft can wait for an agent that cannot start yet.
class const AgentChatComposer({
  super.key,
  required final TerminalComposerController controller,
  required final String workspaceId,
  required final String chatId,
  required final AgentChatComposerSettings settings,
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
  required final AgentChatChooseCallback onChoose,
  required final ValueChanged<String> onOpenFile,
  final bool canSubmit = true,
  final bool canSteer = false,

  /// What Send does instead of sending or queueing, such as declining a
  /// pending approval.
  final String? sendLabel,
  final AleraPopoverController? pickerController,
  final VoidCallback? onRetryCatalog,
  final VoidCallback? onOpenProviderSettings,

  /// Chat actions beside Add Files, such as Delegate Task.
  final Widget? chatActions,
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
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return _handleEnter(event);
    }
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!up && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    // Modified arrows select or jump through the text, and an input method
    // that is composing uses the arrows to pick a candidate.
    final keyboard = HardwareKeyboard.instance;
    final value = _composer.textController.value;
    if (keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        AleraImeCompositionKeyGuard.isComposing(value)) {
      return KeyEventResult.ignored;
    }
    final history = widget.promptHistory();
    final index = _historyIndex;
    // A recalled prompt the user has edited is theirs now.
    if (index != null &&
        (index >= history.length || history[index] != value.text)) {
      _historyIndex = null;
    }
    final text = value.text;
    final browsing = _historyIndex != null;
    if (history.isEmpty ||
        (!browsing && text.isNotEmpty) ||
        !_caretOnEdgeLine(value, up: up)) {
      return KeyEventResult.ignored;
    }
    if (up) {
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

  /// Mod+Enter steers when the running turn accepts it; every other Enter is
  /// left to the composer's own bindings.
  KeyEventResult _handleEnter(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyRepeatEvent ||
        !widget.canSteer ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        !isModModifierPressed() ||
        AleraImeCompositionKeyGuard.isComposing(
          _composer.textController.value,
        )) {
      return KeyEventResult.ignored;
    }
    _send(steer: true);
    return KeyEventResult.handled;
  }

  /// Whether the caret is on the first line ([up]) or the last line of a
  /// recalled multiline prompt, past which the arrow leaves the prompt.
  static bool _caretOnEdgeLine(TextEditingValue value, {required bool up}) {
    final selection = value.selection;
    if (!selection.isValid) return true;
    if (!selection.isCollapsed) return false;
    final offset = selection.extentOffset.clamp(0, value.text.length);
    return up
        ? !value.text.substring(0, offset).contains('\n')
        : !value.text.substring(offset).contains('\n');
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

  void _send({bool steer = false}) {
    if (!widget.canSubmit) return;
    final attachments = <AgentChatAttachment>[
      for (final attachment in _composer.attachments)
        AgentChatAttachment(
          type: attachment.kind == TerminalComposerAttachmentKind.image
              ? AgentChatAttachmentType.localImage
              : AgentChatAttachmentType.file,
          path: attachment.path,
          name: attachment.displayName,
          localSourcePath: attachment.localSourcePath,
          attachmentId: attachment.attachmentId,
          sizeBytes: attachment.sizeBytes,
        ),
    ];
    final text = _composer.textController.text;
    if (!widget.onSend(text, attachments, steer: steer)) return;
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
      _composer.addPathAttachments(paths, localSource: true);
      _composer.focusNode.requestFocus();
    } on Object catch (error) {
      AleraToast.publish(message: 'Could not add files: $error', tone: .error);
    }
  }

  Future<bool> _paste() async {
    try {
      final paths = await widget.clipboard.readFilePaths();
      if (paths.isNotEmpty) {
        _composer.addPathAttachments(paths, localSource: true);
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
        localSource: true,
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
    return DragTarget<TerminalPathDragPayload>(
      onWillAcceptWithDetails: (details) =>
          widget.canSend && details.data.workspaceId == widget.workspaceId,
      onAcceptWithDetails: (details) {
        if (details.data.workspaceId != widget.workspaceId) return;
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
            footer: LayoutBuilder(
              builder: (context, constraints) => _footer(
                targetId,
                compact:
                    constraints.maxWidth <
                    AleraTokens.agentChatComposerCompactWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(String targetId, {required bool compact}) => Padding(
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
          onPressed: widget.canSend ? () => unawaited(_addFiles()) : null,
        ),
        ?widget.chatActions,
        Expanded(
          child: LayoutBuilder(
            builder: (context, strip) {
              final controls = AgentChatComposerControls(
                settings: widget.settings,
                enabled: widget.canSend,
                busy: widget.busy,
                compact: compact,
                pickerController: widget.pickerController,
                onConfigure: widget.onConfigure,
                onChoose: widget.onChoose,
                onRetryCatalog: widget.onRetryCatalog,
                onOpenProviderSettings: widget.onOpenProviderSettings,
              );
              return AleraHorizontalScrollView(
                key: const ValueKey<String>(
                  'agent-chat-composer-controls-scroll',
                ),
                // Compact controls fit the strip, so a long model label
                // ellipsizes instead of scrolling the mode state out of view.
                child: compact
                    ? ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: strip.maxWidth),
                        child: controls,
                      )
                    : controls,
              );
            },
          ),
        ),
        // Keeps a control clipped at the viewport edge from
        // running into the fixed controls.
        const SizedBox(width: AleraTokens.space8),
        AgentChatUsageButton(usage: widget.usage),
        AiDictationControl(
          key: const ValueKey<String>('agent-chat-dictation'),
          targetId: targetId,
        ),
        const SizedBox(width: AleraTokens.space4),
        _SendOrStopButton(
          hasDraft:
              _composer.textController.text.trim().isNotEmpty ||
              _composer.attachments.isNotEmpty,
          canSend: widget.canSend && widget.canSubmit,
          busy: widget.busy,
          canSteer: widget.canSteer,
          canInterrupt: widget.canInterrupt,
          interrupting: widget.interrupting,
          sendLabel: widget.sendLabel,
          onSend: _send,
          onInterrupt: widget.onInterrupt,
        ),
      ],
    ),
  );
}

class const _SendOrStopButton({
  required final bool hasDraft,
  required final bool canSend,
  required final bool busy,
  required final bool canSteer,
  required final bool canInterrupt,
  required final bool interrupting,
  required final VoidCallback onSend,
  required final VoidCallback onInterrupt,
  final String? sendLabel,
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
      tooltip:
          sendLabel ??
          (!busy
              ? 'Send Message'
              : canSteer
              ? 'Queue Message, ${_modEnterLabel()} Steers Into This Turn'
              : 'Queue Message'),
      icon: AleraIcons.arrowUp,
      iconColor: enabled ? AleraTokens.onAccent : AleraTokens.foregroundFaint,
      backgroundColor: enabled ? AleraTokens.accent : AleraTokens.surface,
      borderRadius: AleraTokens.radiusPill,
      minSize: AleraTokens.space32,
      onPressed: enabled ? onSend : null,
    );
  }
}

String _modEnterLabel() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘Enter' : 'Ctrl+Enter';
