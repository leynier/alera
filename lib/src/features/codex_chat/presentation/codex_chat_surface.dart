import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
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
import 'package:alera/src/features/workbench/application/terminal_composer_workspace_attachment.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
part 'codex_chat_surface_composer_logic.dart';
part 'codex_chat_surface_composer_menu_entries.dart';
part 'codex_chat_surface_composer_history.dart';
part 'codex_chat_surface_composer_attachments.dart';
part 'codex_chat_surface_composer_catalog.dart';
part 'codex_chat_surface_composer_context.dart';
part 'codex_chat_surface_composer_menus.dart';
part 'codex_chat_surface_composer_model_menu.dart';
part 'codex_chat_surface_composer_overlays.dart';
part 'codex_chat_surface_composer_quick_open.dart';
part 'codex_chat_resume_picker.dart';
part 'codex_chat_surface_saved_prompts.dart';
part 'codex_chat_surface_dialogs.dart';
part 'codex_chat_surface_goal.dart';
part 'codex_chat_review_dialog.dart';
part 'codex_chat_surface_draft_actions.dart';
part 'codex_chat_surface_link_handling.dart';
part 'codex_chat_surface_plan_actions.dart';
part 'codex_chat_surface_session_actions.dart';
part 'codex_chat_surface_markdown_code.dart';
part 'codex_chat_surface_timeline.dart';
part 'codex_chat_surface_timeline_cells.dart';
part 'codex_chat_surface_timeline_activity.dart';
part 'codex_chat_surface_timeline_notices.dart';
part 'codex_chat_surface_timeline_plan.dart';
part 'codex_chat_surface_timeline_plan_question.dart';
part 'codex_chat_surface_recovery_question.dart';
part 'codex_chat_surface_timeline_messages.dart';
part 'codex_chat_surface_timeline_message_actions.dart';
part 'codex_chat_surface_timeline_tool_details.dart';
part 'codex_chat_surface_timeline_tool_media.dart';
part 'codex_chat_surface_timeline_tool_projection.dart';
part 'codex_chat_surface_timeline_tool_value.dart';
part 'codex_chat_surface_timeline_helpers.dart';
part 'codex_chat_surface_timeline_worked.dart';
part 'codex_chat_surface_timeline_worked_projection.dart';
part 'codex_chat_surface_timeline_progress.dart';
part 'codex_chat_surface_shimmer.dart';
part 'codex_chat_surface_timeline_groups.dart';
part 'codex_chat_surface_timeline_widget.dart';
part 'codex_chat_surface_timeline_viewport.dart';
part 'codex_chat_surface_timeline_turn.dart';
part 'codex_chat_surface_timeline_projection.dart';
part 'codex_chat_surface_timeline_turn_projection.dart';
part 'codex_chat_surface_controller_views.dart';
part 'codex_chat_surface_timeline_secondary.dart';
part 'codex_chat_surface_timeline_approvals.dart';
part 'codex_chat_surface_question_queue.dart';
part 'codex_chat_surface_timeline_questions.dart';
part 'codex_chat_surface_prompt_controls.dart';
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
  final GlobalKey<_CodexTimelineState> _timelineViewKey = GlobalKey();
  final List<CodexInputAttachment> _attachments = <CodexInputAttachment>[];
  final List<CodexDraftItem> _draftItems = <CodexDraftItem>[];
  final ValueNotifier<int> _planDecisionRevision = ValueNotifier<int>(0);
  final TerminalClipboard _clipboard = const NativeTerminalClipboard();
  late final WorkspaceFileService _workspaceFiles;
  late final CodexComposerDraftStore _draftStore;
  List<native.CodexSavedPrompt> _savedPrompts =
      const <native.CodexSavedPrompt>[];
  int _savedPromptLoadGeneration = 0;
  int _historyLoadGeneration = 0;
  bool _showRawLogs = false;
  bool _restoringDraft = false;
  bool _loadingEarlier = false;

  void _setSurfaceState(VoidCallback callback) {
    setState(callback);
    _persistCurrentDraft();
  }

  void _setDraftState(VoidCallback callback) {
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
    _timeline.addListener(_loadEarlierHistory);
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
      _historyLoadGeneration += 1;
      _loadingEarlier = false;
      _timelineViewKey.currentState?.releaseViewportAnchor();
      _restoreDraft(widget.tab.id);
      _savedPrompts = const <native.CodexSavedPrompt>[];
      unawaited(_loadSavedPrompts(widget.workspace.path));
    } else if (oldWidget.workspace.path != widget.workspace.path) {
      unawaited(_loadSavedPrompts(widget.workspace.path));
    }
  }

  @override
  void dispose() {
    _timeline.removeListener(_loadEarlierHistory);
    _composer.removeListener(_persistCurrentDraft);
    _composer.dispose();
    _composerFocus.dispose();
    _timeline.dispose();
    _planDecisionRevision.dispose();
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
    final provider = codexChatControllerProvider(widget.tab.id);
    final activeCwd = ref.watch(provider.select((state) => state.activeCwd));
    final activeWorkspacePath = activeCwd?.trim().isNotEmpty == true
        ? activeCwd!.trim()
        : widget.workspace.path;
    final controller = ref.read(provider.notifier);
    ref.listen<String?>(
      provider.select((value) => value.activeCwd),
      (_, activeCwd) =>
          unawaited(_loadSavedPrompts(activeCwd ?? widget.workspace.path)),
    );
    return _CodexShimmerScope(
      child: _CodexLinkScope(
        onOpenLink: _openMarkdownLink,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AleraTokens.bg),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _CodexControllerTimeline(
                    tabId: widget.tab.id,
                    workspacePath: activeWorkspacePath,
                    fallbackTitle: widget.tab.title,
                    showRawLogs: _showRawLogs,
                    timeline: _timeline,
                    timelineKey: _timelineViewKey,
                    loadingEarlier: _loadingEarlier,
                    planDecisionRevision: _planDecisionRevision,
                    onOpenAttachment: (path, {required isImage}) =>
                        _openAttachment(path, isImage: isImage),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: _CodexControllerFooter(
                    tabId: widget.tab.id,
                    composerController: _composer,
                    composerFocus: _composerFocus,
                    attachments: _attachments,
                    draftItems: _draftItems,
                    savedPrompts: _savedPrompts,
                    workspacePath: activeWorkspacePath,
                    workspaceFiles: _workspaceFiles,
                    onEditQueued: (index, message) =>
                        _editQueued(controller, index, message),
                    onDraftItemSelected: _addDraftItem,
                    onCommand: (state, command) => _runComposerCommand(
                      context,
                      controller,
                      state,
                      command,
                    ),
                    onSend: () => _send(controller),
                    onAddAttachment: _addAttachment,
                    onPaste: _paste,
                    onDropAttachments: _addPathAttachments,
                    onRemoveAttachment: _removeAttachment,
                    onOpenAttachment: (path, {required isImage}) =>
                        _openAttachment(path, isImage: isImage),
                    onRemoveDraftItem: _removeDraftItem,
                    onSubmitQuestions: (request, answers) =>
                        _submitQuestions(controller, request, answers),
                    onPlanInteraction: _notifyPlanDecision,
                    onImplementPlan: () => _implementPlan(controller),
                    onDeclinePlan: () => _declinePlan(controller),
                    onRefinePlan: (value) => _refinePlan(controller, value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final originatingTabId = widget.tab.id;
    try {
      final paths = await _clipboard.readFilePaths();
      if (!mounted || widget.tab.id != originatingTabId) return;
      if (paths.isNotEmpty) {
        await _addPathAttachments(paths);
        return;
      }
    } catch (_) {
      // Text and image clipboard formats remain available below.
    }
    try {
      final imagePath = await _clipboard.saveImageAsTempFile();
      if (!mounted || widget.tab.id != originatingTabId) return;
      if (imagePath != null && imagePath.isNotEmpty) {
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
      if (!mounted || widget.tab.id != originatingTabId) return;
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
    final token = attachment.tokenText;
    if (attachment.origin != CodexInputAttachmentOrigin.mention ||
        token == null ||
        token.isEmpty) {
      return;
    }
    final range = codexFileReferenceRange(
      _composer.text,
      token,
      preferredStart: attachment.tokenStart,
    );
    if (range == null) return;
    final updated = _composer.text.replaceRange(range.start, range.end, '');
    _composer.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
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
    final originatingTabId = widget.tab.id;
    final files = await openFiles();
    if (files.isEmpty || !mounted || widget.tab.id != originatingTabId) {
      return;
    }
    final additions = <CodexInputAttachment>[
      for (final file in files)
        CodexInputAttachment(
          id: const Uuid().v4(),
          path: file.path,
          displayName: file.name,
          isImage: isCodexImagePath(file.path),
        ),
    ];
    _setSurfaceState(() => _attachments.addAll(additions));
    final sizes = await Future.wait(
      additions.map((attachment) async {
        try {
          return (
            id: attachment.id,
            size: await File(attachment.path).length(),
          );
        } catch (_) {
          return (id: attachment.id, size: null);
        }
      }),
    );
    if (!mounted || widget.tab.id != originatingTabId) return;
    final sizeById = <String?, int>{
      for (final item in sizes)
        if (item.size case final int size) item.id: size,
    };
    if (!_attachments.any((item) => sizeById.containsKey(item.id))) return;
    _setDraftState(() {
      for (var index = 0; index < _attachments.length; index++) {
        final attachment = _attachments[index];
        final size = sizeById[attachment.id];
        if (size == null) continue;
        _attachments[index] = attachment.copyWith(sizeBytes: size);
      }
    });
  }
}
