import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;

part 'codex_chat_surface_composer.dart';
part 'codex_chat_surface_header.dart';
part 'codex_chat_surface_timeline.dart';
part 'codex_chat_surface_timeline_requests.dart';

class CodexChatSurface extends ConsumerStatefulWidget {
  const CodexChatSurface({
    super.key,
    required this.workspace,
    required this.tab,
    this.autofocus = false,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final bool autofocus;

  @override
  ConsumerState<CodexChatSurface> createState() => _CodexChatSurfaceState();
}

class _CodexChatSurfaceState extends ConsumerState<CodexChatSurface> {
  late final TextEditingController _composer;
  late final FocusNode _composerFocus;
  final ScrollController _timeline = ScrollController();
  final List<CodexInputAttachment> _attachments = <CodexInputAttachment>[];
  final TerminalClipboard _clipboard = const NativeTerminalClipboard();
  bool _showRawLogs = false;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController();
    _composerFocus = FocusNode();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codexChatControllerProvider(widget.tab.id));
    final controller = ref.read(
      codexChatControllerProvider(widget.tab.id).notifier,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CodexHeader(
            state: state,
            onModelChanged: controller.setModel,
            onReasoningChanged: controller.setReasoning,
            onSpeedChanged: controller.setSpeed,
            onPermissionChanged: controller.setPermissionMode,
            onPlanChanged: controller.setPlanMode,
            onCollaborationChanged: controller.setCollaborationMode,
            onCompact: controller.compact,
            onReview: () => _startReview(context, controller),
            onRename: () => _rename(context, controller),
            onInsertToken: _insertComposerToken,
            onToggleRawLogs: () => setState(() => _showRawLogs = !_showRawLogs),
          ),
          const Divider(
            height: AleraTokens.dividerExtent,
            color: AleraTokens.borderSubtle,
          ),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.error != null &&
                      state.snapshot.timelineCells.isEmpty &&
                      state.snapshot.events.isEmpty
                ? _CodexFailure(
                    message: state.error!,
                    onRetry: controller.retry,
                  )
                : _CodexTimeline(
                    snapshot: state.snapshot,
                    showRawLogs: _showRawLogs,
                    timeline: _timeline,
                    onApproval: controller.respondApproval,
                    onQuestion: controller.submitQuestions,
                    onElicitation: controller.respondElicitation,
                    onReject: controller.rejectRequest,
                    onImplementPlan: controller.implementPlan,
                  ),
          ),
          if (state.error != null)
            _CodexInlineError(message: state.error!, onRetry: controller.retry),
          if (state.queuedMessages.isNotEmpty)
            _CodexQueueBar(
              messages: state.queuedMessages,
              onRemove: controller.removeQueuedMessage,
              onEdit: (index, message) =>
                  _editQueued(context, controller, index, message),
            ),
          _CodexComposer(
            controller: _composer,
            focusNode: _composerFocus,
            busy: state.busy,
            interrupting: state.interrupting,
            attachments: _attachments,
            onSend: () => _send(controller),
            onSteer: () => _steer(controller),
            onStop: controller.stop,
            onPaste: _pasteText,
            onRemoveAttachment: _removeAttachment,
          ),
        ],
      ),
    );
  }

  Future<void> _send(CodexChatController controller) async {
    final text = _composer.text;
    final attachments = List<CodexInputAttachment>.of(_attachments);
    _composer.clear();
    _attachments.clear();
    await controller.send(text, attachments: attachments);
    if (mounted) _composerFocus.requestFocus();
  }

  Future<void> _steer(CodexChatController controller) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await controller.steer(text);
    if (mounted) _composerFocus.requestFocus();
  }

  Future<void> _editQueued(
    BuildContext context,
    CodexChatController controller,
    int index,
    CodexQueuedMessage message,
  ) async {
    final input = TextEditingController(text: message.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Queued Message'),
        content: TextField(controller: input, autofocus: true, maxLines: 5),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (text != null) {
      controller.editQueuedMessage(
        index,
        text: text,
        attachments: message.attachments,
      );
    }
  }

  Future<void> _pasteText() async {
    try {
      final paths = await _clipboard.readFilePaths();
      if (paths.isNotEmpty) {
        setState(() {
          _attachments.addAll(
            paths.map(
              (path) =>
                  CodexInputAttachment(path: path, isImage: _isImagePath(path)),
            ),
          );
        });
        return;
      }
    } catch (_) {
      // Text and image clipboard formats remain available below.
    }
    final text = await _clipboard.readText();
    if (text != null && text.isNotEmpty) {
      final selection = _composer.selection;
      _composer.text = selection.isValid
          ? (_composer.text.replaceRange(selection.start, selection.end, text))
          : '${_composer.text}$text';
      _composer.selection = TextSelection.collapsed(
        offset: _composer.text.length,
      );
      return;
    }
    try {
      final imagePath = await _clipboard.saveImageAsTempFile();
      if (imagePath != null && imagePath.isNotEmpty && mounted) {
        setState(() {
          _attachments.add(
            CodexInputAttachment(path: imagePath, isImage: true),
          );
        });
      }
    } catch (_) {
      // Image clipboard support is optional on platforms without the native
      // clipboard bridge.
    }
  }

  void _removeAttachment(CodexInputAttachment attachment) {
    setState(() => _attachments.remove(attachment));
  }

  void _insertComposerToken(String token) {
    final current = _composer.text.trimRight();
    _composer.text = current.isEmpty ? token : '$current $token';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
    _composerFocus.requestFocus();
  }

  Future<void> _rename(
    BuildContext context,
    CodexChatController controller,
  ) async {
    final input = TextEditingController(text: widget.tab.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Codex Thread'),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null) await controller.rename(name);
  }

  Future<void> _startReview(
    BuildContext context,
    CodexChatController controller,
  ) async {
    final input = TextEditingController();
    var target = 'uncommittedChanges';
    var delivery = 'inline';
    final selection = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: target,
                decoration: const InputDecoration(labelText: 'Target'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'uncommittedChanges',
                    child: Text('Uncommitted Changes'),
                  ),
                  DropdownMenuItem(
                    value: 'baseBranch',
                    child: Text('Base Branch'),
                  ),
                  DropdownMenuItem(value: 'commit', child: Text('Commit')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => target = value);
                },
              ),
              if (target != 'uncommittedChanges')
                TextField(
                  controller: input,
                  decoration: InputDecoration(
                    labelText: switch (target) {
                      'baseBranch' => 'Branch',
                      'commit' => 'Commit Sha',
                      _ => 'Instructions',
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: delivery,
                decoration: const InputDecoration(labelText: 'Delivery'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'inline', child: Text('Inline')),
                  DropdownMenuItem(value: 'detached', child: Text('Detached')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => delivery = value);
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(<String, String?>{
                'target': target,
                'argument': input.text,
                'delivery': delivery,
              }),
              child: const Text('Start Review'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (selection == null || !mounted) return;
    await controller.startReview(
      target: selection['target'] ?? 'uncommittedChanges',
      argument: selection['argument'],
      delivery: selection['delivery'],
    );
  }
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp');
}
