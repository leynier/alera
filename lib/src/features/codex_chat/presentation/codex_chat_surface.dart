import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/application/codex_composer_draft_store.dart';
import 'package:alera/src/features/codex_chat/domain/codex_attachment_types.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:alera/src/features/codex_chat/domain/codex_file_reference.dart';
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
part 'codex_chat_resume_picker.dart';
part 'codex_chat_surface_saved_prompts.dart';
part 'codex_chat_surface_dialogs.dart';
part 'codex_chat_surface_draft_actions.dart';
part 'codex_chat_surface_session_actions.dart';
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
  late final CodexComposerDraftStore _draftStore;
  List<native.CodexSavedPrompt> _savedPrompts =
      const <native.CodexSavedPrompt>[];
  int _savedPromptLoadGeneration = 0;
  bool _showRawLogs = false;
  bool _restoringDraft = false;

  void _setSurfaceState(VoidCallback callback) {
    setState(callback);
    _persistCurrentDraft();
  }

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(codexComposerDraftStoreProvider);
    final draft = _draftStore.read(widget.tab.id);
    _composer = TextEditingController.fromValue(draft.value)
      ..addListener(_persistCurrentDraft);
    _attachments.addAll(draft.attachments);
    _draftItems.addAll(draft.draftItems);
    _composerFocus = FocusNode();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    unawaited(_loadSavedPrompts(widget.workspace.path));
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerFocus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CodexChatSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _restoreDraft(widget.tab.id);
      _savedPrompts = const <native.CodexSavedPrompt>[];
      unawaited(_loadSavedPrompts(widget.workspace.path));
    } else if (oldWidget.workspace.path != widget.workspace.path) {
      unawaited(_loadSavedPrompts(widget.workspace.path));
    }
  }

  @override
  void dispose() {
    _composer.removeListener(_persistCurrentDraft);
    _composer.dispose();
    _composerFocus.dispose();
    _timeline.dispose();
    super.dispose();
  }

  void _restoreDraft(String tabId) {
    final draft = _draftStore.read(tabId);
    _restoringDraft = true;
    _composer.value = draft.value;
    _attachments
      ..clear()
      ..addAll(draft.attachments);
    _draftItems
      ..clear()
      ..addAll(draft.draftItems);
    _restoringDraft = false;
  }

  void _persistCurrentDraft() {
    if (_restoringDraft) return;
    _persistDraft(widget.tab.id);
  }

  void _persistDraft(String tabId) {
    _draftStore.write(
      tabId,
      CodexComposerDraft(
        value: _composer.value,
        attachments: List<CodexInputAttachment>.unmodifiable(_attachments),
        draftItems: List<CodexDraftItem>.unmodifiable(_draftItems),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codexChatControllerProvider(widget.tab.id));
    final controller = ref.read(
      codexChatControllerProvider(widget.tab.id).notifier,
    );
    final activeWorkspacePath = state.activeCwd ?? widget.workspace.path;
    ref.listen<String?>(
      codexChatControllerProvider(
        widget.tab.id,
      ).select((value) => value.activeCwd),
      (_, activeCwd) =>
          unawaited(_loadSavedPrompts(activeCwd ?? widget.workspace.path)),
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
                    workspacePath: activeWorkspacePath,
                    title: state.snapshot.title ?? widget.tab.title,
                    planMode: state.planMode,
                    showRawLogs: _showRawLogs,
                    timeline: _timeline,
                    historyNextCursor: state.historyNextCursor,
                    onLoadHistory: controller.loadHistory,
                    onApproval: controller.respondApproval,
                    onQuestion: controller.submitQuestions,
                    onQuestionInteraction:
                        controller.snoozeQuestionAutoResolution,
                    onElicitation: controller.respondElicitation,
                    onReject: controller.rejectRequest,
                    onImplementPlan: controller.implementPlan,
                    onDeclinePlan: controller.declinePlan,
                    onRefinePlan: controller.refinePlan,
                  ),
          ),
          if (state.error != null)
            _CodexInlineError(message: state.error!, onRetry: controller.retry),
          if (state.recovery != null)
            _CodexRecoveryBanner(
              message: state.recovery!.message,
              onContinue: controller.recoverThread,
            ),
          if (state.queuedMessages.isNotEmpty)
            _CodexQueueBar(
              messages: state.queuedMessages,
              canSteer: controller.canSteer,
              onRemove: controller.removeQueuedMessage,
              onEdit: (index, message) =>
                  _editQueued(controller, index, message),
              onSteer: (index, message) async {
                final sent = await controller.steer(
                  message.text,
                  attachments: message.attachments,
                  draftItems: message.draftItems,
                );
                if (sent) controller.removeQueuedMessage(index);
              },
            ),
          if (state.recovery == null)
            _CodexComposer(
              controller: _composer,
              focusNode: _composerFocus,
              busy: state.busy,
              interrupting: state.interrupting,
              attachments: _attachments,
              draftItems: _draftItems,
              savedPrompts: _savedPrompts,
              state: state,
              workspacePath: activeWorkspacePath,
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
        _setSurfaceState(() {
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
        _setSurfaceState(() {
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
    _setSurfaceState(() => _attachments.remove(attachment));
  }

  void _addDraftItem(CodexDraftItem item) {
    if (_draftItems.any(
      (existing) => existing.kind == item.kind && existing.path == item.path,
    )) {
      return;
    }
    var storedItem = item;
    if (item.kind == CodexDraftItemKind.app && item.tokenText != null) {
      final current = _composer.text;
      final prefix = current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
      final token = '$prefix${item.tokenText} ';
      final selection = _composer.selection;
      final start = selection.start < 0 ? current.length : selection.start;
      final end = selection.end < 0 ? current.length : selection.end;
      storedItem = item.copyWith(tokenStart: start + prefix.length);
      _composer.value = _composer.value.copyWith(
        text: current.replaceRange(start, end, token),
        selection: TextSelection.collapsed(offset: start + token.length),
        composing: TextRange.empty,
      );
    }
    _setSurfaceState(() => _draftItems.add(storedItem));
    _composerFocus.requestFocus();
  }

  void _removeDraftItem(CodexDraftItem item) {
    _setSurfaceState(
      () => _draftItems.removeWhere((value) => value.id == item.id),
    );
    final token = item.tokenText;
    if (token != null && token.isNotEmpty) {
      final range = codexFileReferenceRange(
        _composer.text,
        token,
        preferredStart: item.tokenStart,
      );
      if (range != null) {
        final updated = _composer.text.replaceRange(range.start, range.end, '');
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
    _setSurfaceState(() => _attachments.addAll(additions));
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
