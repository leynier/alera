import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:alera/src/features/codex_chat/domain/codex_attachment_types.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_saved_prompt_expander.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/git/git_providers.dart';

part 'codex_chat_surface_composer.dart';
part 'codex_chat_surface_composer_attachments.dart';
part 'codex_chat_surface_composer_context.dart';
part 'codex_chat_surface_composer_menus.dart';
part 'codex_chat_surface_composer_overlays.dart';
part 'codex_chat_surface_composer_quick_open.dart';
part 'codex_chat_surface_saved_prompts.dart';
part 'codex_chat_surface_dialogs.dart';
part 'codex_chat_surface_draft_actions.dart';
part 'codex_chat_surface_markdown_code.dart';
part 'codex_chat_surface_timeline.dart';
part 'codex_chat_surface_timeline_cells.dart';
part 'codex_chat_surface_timeline_activity.dart';
part 'codex_chat_surface_timeline_messages.dart';
part 'codex_chat_surface_timeline_tool_details.dart';
part 'codex_chat_surface_timeline_helpers.dart';
part 'codex_chat_surface_timeline_groups.dart';
part 'codex_chat_surface_timeline_approvals.dart';
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
  final List<CodexDraftItem> _draftItems = <CodexDraftItem>[];
  final TerminalClipboard _clipboard = const NativeTerminalClipboard();
  late final WorkspaceFileService _workspaceFiles;
  List<native.CodexSavedPrompt> _savedPrompts =
      const <native.CodexSavedPrompt>[];
  bool _showRawLogs = false;

  void _setSurfaceState(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController();
    _composerFocus = FocusNode();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    unawaited(_loadSavedPrompts());
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerFocus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CodexChatSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path) {
      unawaited(_loadSavedPrompts());
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
                    workspacePath: widget.workspace.path,
                    title: state.snapshot.title ?? widget.tab.title,
                    planMode: state.planMode,
                    showRawLogs: _showRawLogs,
                    timeline: _timeline,
                    onApproval: controller.respondApproval,
                    onQuestion: controller.submitQuestions,
                    onElicitation: controller.respondElicitation,
                    onReject: controller.rejectRequest,
                    onImplementPlan: controller.implementPlan,
                    onDeclinePlan: controller.declinePlan,
                    onRefinePlan: controller.refinePlan,
                  ),
          ),
          if (state.error != null)
            _CodexInlineError(message: state.error!, onRetry: controller.retry),
          if (state.queuedMessages.isNotEmpty)
            _CodexQueueBar(
              messages: state.queuedMessages,
              onRemove: controller.removeQueuedMessage,
              onEdit: (index, message) =>
                  _editQueued(controller, index, message),
              onSteer: (index, message) async {
                await controller.steer(
                  message.text,
                  attachments: message.attachments,
                  draftItems: message.draftItems,
                );
                controller.removeQueuedMessage(index);
              },
            ),
          _CodexComposer(
            controller: _composer,
            focusNode: _composerFocus,
            busy: state.busy,
            interrupting: state.interrupting,
            attachments: _attachments,
            draftItems: _draftItems,
            savedPrompts: _savedPrompts,
            state: state,
            workspacePath: widget.workspace.path,
            workspaceFiles: _workspaceFiles,
            onModelChanged: controller.setModel,
            onReasoningChanged: controller.setReasoning,
            onSpeedChanged: controller.setSpeed,
            onPermissionChanged: controller.setPermissionMode,
            onPlanChanged: controller.setPlanMode,
            onCollaborationChanged: controller.setCollaborationMode,
            onDraftItemSelected: _addDraftItem,
            onCommand: (command) =>
                _runComposerCommand(context, controller, state, command),
            onSend: () => _send(controller),
            onStop: controller.stop,
            onAddAttachment: _addAttachment,
            onPaste: _paste,
            onRemoveAttachment: _removeAttachment,
            onRemoveDraftItem: _removeDraftItem,
          ),
        ],
      ),
    );
  }

  Future<void> _paste() async {
    try {
      final paths = await _clipboard.readFilePaths();
      if (paths.isNotEmpty) {
        setState(() {
          _attachments.addAll(
            paths.map(
              (path) => CodexInputAttachment(
                path: path,
                isImage: isCodexImagePath(path),
              ),
            ),
          );
        });
        return;
      }
    } catch (_) {
      // Text and image clipboard formats remain available below.
    }
    try {
      final imagePath = await _clipboard.saveImageAsTempFile();
      if (imagePath != null && imagePath.isNotEmpty && mounted) {
        setState(() {
          _attachments.add(
            CodexInputAttachment(path: imagePath, isImage: true),
          );
        });
        return;
      }
    } catch (_) {
      // Image clipboard support is optional on platforms without the native
      // clipboard bridge.
    }
    try {
      final text = await _clipboard.readText();
      if (text == null || text.isEmpty) return;
      final selection = _composer.selection;
      final start = selection.isValid ? selection.start : _composer.text.length;
      final end = selection.isValid ? selection.end : _composer.text.length;
      final next = _composer.text.replaceRange(start, end, text);
      _composer.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
    } catch (_) {
      // Clipboard failures leave the current draft untouched.
    }
  }

  void _removeAttachment(CodexInputAttachment attachment) {
    setState(() => _attachments.remove(attachment));
  }

  void _addDraftItem(CodexDraftItem item) {
    if (_draftItems.any(
      (existing) => existing.kind == item.kind && existing.path == item.path,
    )) {
      return;
    }
    setState(() => _draftItems.add(item));
    if (item.kind == CodexDraftItemKind.app && item.tokenText != null) {
      final current = _composer.text;
      final prefix = current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
      final token = '$prefix${item.tokenText} ';
      final selection = _composer.selection;
      final start = selection.start < 0 ? current.length : selection.start;
      final end = selection.end < 0 ? current.length : selection.end;
      _composer.value = _composer.value.copyWith(
        text: current.replaceRange(start, end, token),
        selection: TextSelection.collapsed(offset: start + token.length),
        composing: TextRange.empty,
      );
    }
    _composerFocus.requestFocus();
  }

  void _removeDraftItem(CodexDraftItem item) {
    setState(() => _draftItems.removeWhere((value) => value.id == item.id));
    final token = item.tokenText;
    if (token != null && token.isNotEmpty) {
      final updated = _composer.text
          .replaceFirst('$token ', '')
          .replaceFirst(token, '');
      if (updated != _composer.text) {
        _composer.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: updated.length),
        );
      }
    }
  }

  Future<void> _addAttachment() async {
    final files = await openFiles();
    if (files.isEmpty || !mounted) return;
    final additions = <CodexInputAttachment>[];
    for (final file in files) {
      int? size;
      try {
        size = await File(file.path).length();
      } catch (_) {
        // Size is display metadata only.
      }
      additions.add(
        CodexInputAttachment(
          id: const Uuid().v4(),
          path: file.path,
          displayName: file.name,
          isImage: isCodexImagePath(file.path),
          sizeBytes: size,
        ),
      );
    }
    setState(() => _attachments.addAll(additions));
  }

  Future<void> _runComposerCommand(
    BuildContext context,
    CodexChatController controller,
    CodexChatState state,
    CodexComposerCommand command,
  ) async {
    switch (command) {
      case CodexComposerCommand.newChat:
      case CodexComposerCommand.clear:
        await ref
            .read(workbenchControllerProvider.notifier)
            .createCodexTab(widget.workspace);
      case CodexComposerCommand.compact:
        await controller.compact();
      case CodexComposerCommand.review:
        await _startReview(context, controller);
      case CodexComposerCommand.plan:
        controller.setPlanMode(!state.planMode);
      case CodexComposerCommand.model:
        final model = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select Model'),
            children: <Widget>[
              for (final option in state.models)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(option.id),
                  child: Text(option.label),
                ),
            ],
          ),
        );
        controller.setModel(model);
      case CodexComposerCommand.permissions:
        final mode = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Select Approval Mode'),
            children: <Widget>[
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('on-request'),
                child: const Text('Ask First'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('never'),
                child: const Text('Full Access'),
              ),
            ],
          ),
        );
        if (mode != null) controller.setPermissionMode(mode);
      case CodexComposerCommand.mention:
        _insertAtCursor('@');
      case CodexComposerCommand.skills:
        await _pickCatalog(context, state.skills, skill: true);
      case CodexComposerCommand.apps:
        await _pickCatalog(context, state.apps, skill: false);
      case CodexComposerCommand.status:
        await _showStatus(context, state);
      case CodexComposerCommand.rename:
        await _rename(context, controller);
      case CodexComposerCommand.logs:
        setState(() => _showRawLogs = !_showRawLogs);
    }
    if (mounted) _composerFocus.requestFocus();
  }

  void _insertAtCursor(String text) {
    final value = _composer.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0
        ? value.text.length
        : value.selection.end;
    _composer.value = value.copyWith(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _pickCatalog(
    BuildContext context,
    List<Map<String, Object?>> items, {
    required bool skill,
  }) async {
    if (items.isEmpty) return;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CodexCatalogPickerDialog(
        title: skill ? 'Select A Skill' : 'Select An App',
        items: items,
        searchHint: skill ? 'Filter Skills' : 'Filter Apps',
      ),
    );
    if (selected == null) return;
    final name = _catalogName(selected);
    final path = skill
        ? selected['path']?.toString().trim()
        : _catalogConnector(selected);
    if (path == null || path.isEmpty) return;
    _addDraftItem(
      CodexDraftItem(
        id: '${skill ? 'skill' : 'app'}-$path',
        kind: skill ? CodexDraftItemKind.skill : CodexDraftItemKind.app,
        name: name,
        path: path,
        tokenText: skill ? null : '\$$name',
      ),
    );
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
}
