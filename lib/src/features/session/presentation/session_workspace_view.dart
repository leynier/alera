import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/commands/command_parser.dart';
import 'package:alera/src/features/session/domain/commands/command_registry.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/domain/review_preset_selection.dart';
import 'package:alera/src/features/session/presentation/widgets/approval_card.dart';
import 'package:alera/src/features/session/presentation/widgets/chat_timeline_list.dart';
import 'package:alera/src/features/session/presentation/widgets/composer.dart';
import 'package:alera/src/features/session/presentation/widgets/composer_text_controller.dart';
import 'package:alera/src/features/session/presentation/widgets/message_queue_bar.dart';
import 'package:alera/src/features/session/presentation/widgets/queue_message_edit_dialog.dart';
import 'package:alera/src/features/session/presentation/widgets/raw_log.dart';
import 'package:alera/src/features/session/presentation/widgets/user_input_card.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Re-export for test compatibility.
export 'package:alera/src/features/session/presentation/widgets/markdown_helpers.dart'
    show copyMouseConnectionDetector;

class SessionWorkspaceView extends StatefulWidget {
  const SessionWorkspaceView({
    super.key,
    required this.state,
    required this.onSendInput,
    required this.onInterruptTurn,
    required this.isTurnRunning,
    required this.isInterrupting,
    required this.onModelChanged,
    required this.activeReasoningEffort,
    required this.supportedReasoningEfforts,
    required this.onReasoningEffortChanged,
    required this.isMarkdownEnabled,
    required this.onMarkdownModeChanged,
    required this.rawLogExpanded,
    required this.onAddAttachment,
    this.onPasteImage,
    required this.onRemoveAttachment,
    required this.onRemoveFromQueue,
    required this.onSteerQueuedMessage,
    required this.onStartEditingPendingMessage,
    required this.onUpdatePendingMessage,
    required this.onDeletePendingMessage,
    required this.onFinishEditingPendingMessage,
    required this.onPlanModeToggled,
    required this.onImplementPlanPressed,
    required this.onPermissionModeToggled,
    this.onPermissionModeSelected,
    required this.onApproveRequest,
    required this.onDeclineRequest,
    required this.onSubmitUserInput,
    required this.onDismissUserInput,
    this.onListSkills,
    this.onListApps,
    this.onListReviewBranches,
    this.onAddDraftItem,
    this.onRemoveDraftItem,
    this.onStartReviewFromPreset,
    this.onCompact,
  });

  final SessionState state;
  final ValueChanged<String> onSendInput;
  final VoidCallback onInterruptTurn;
  final bool isTurnRunning;
  final bool isInterrupting;
  final ValueChanged<String> onModelChanged;
  final String activeReasoningEffort;
  final List<String> supportedReasoningEfforts;
  final ValueChanged<String> onReasoningEffortChanged;
  final bool isMarkdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;
  final bool rawLogExpanded;
  final VoidCallback onAddAttachment;
  final ValueChanged<File>? onPasteImage;
  final ValueChanged<String> onRemoveAttachment;
  final ValueChanged<String> onRemoveFromQueue;
  final ValueChanged<String> onSteerQueuedMessage;
  final ValueChanged<String> onStartEditingPendingMessage;
  final void Function(
    String id,
    String text,
    List<ComposerAttachment> attachments,
  )
  onUpdatePendingMessage;
  final ValueChanged<String> onDeletePendingMessage;
  final VoidCallback onFinishEditingPendingMessage;
  final VoidCallback onPlanModeToggled;
  final Future<void> Function() onImplementPlanPressed;
  final VoidCallback onPermissionModeToggled;
  final ValueChanged<PermissionMode>? onPermissionModeSelected;
  final Future<void> Function(Object requestId, {bool forSession})
  onApproveRequest;
  final Future<void> Function(Object requestId) onDeclineRequest;
  final ValueChanged<Map<String, dynamic>> onSubmitUserInput;
  final VoidCallback onDismissUserInput;
  final Future<List<CodexSkillMetadata>> Function()? onListSkills;
  final Future<List<CodexAppInfo>> Function()? onListApps;
  final Future<List<String>> Function()? onListReviewBranches;
  final ValueChanged<ComposerDraftItem>? onAddDraftItem;
  final ValueChanged<String>? onRemoveDraftItem;
  final Future<void> Function(ReviewPresetSelection preset, {String? value})?
  onStartReviewFromPreset;
  final VoidCallback? onCompact;

  @override
  State<SessionWorkspaceView> createState() => _SessionWorkspaceViewState();
}

class _SessionWorkspaceViewState extends State<SessionWorkspaceView> {
  static const double _contentMaxWidth = 720;
  static const double _timelineExtraInset = AleraTokens.space8;
  static const double _timelineContentMaxWidth =
      _contentMaxWidth - (AleraTokens.space12 * 2) - _timelineExtraInset;
  static const double _bottomTolerancePx = 1;

  late final _inputController = ComposerTextController()
    ..workspacePath = widget.state.selectedWorkspacePath;
  final _commandRegistry = const CommandRegistry();
  final Set<String> _expandedWorkedTurns = <String>{};
  final ScrollController _timelineScrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _pendingScrollAfterSend = false;
  final GlobalKey<ComposerState> _composerKey = GlobalKey<ComposerState>();

  @override
  void initState() {
    super.initState();
    _timelineScrollController.addListener(_handleTimelineScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollToBottomVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant SessionWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.selectedWorkspacePath !=
        widget.state.selectedWorkspacePath) {
      _inputController.workspacePath = widget.state.selectedWorkspacePath;
    }
    if (oldWidget.state.activeSessionId != widget.state.activeSessionId) {
      _expandedWorkedTurns.clear();
    }
    final timelineChanged = !identical(
      oldWidget.state.timelineCells,
      widget.state.timelineCells,
    );
    final hasNonUserTimelineChanges =
        timelineChanged &&
        _hasNonUserTimelineChanges(
          oldWidget.state.timelineCells,
          widget.state.timelineCells,
        );
    final shouldAutoScrollForAi =
        hasNonUserTimelineChanges &&
        _isAtBottom(tolerancePx: _bottomTolerancePx);
    final shouldAutoScrollForSend = _pendingScrollAfterSend && timelineChanged;
    if (shouldAutoScrollForAi || shouldAutoScrollForSend) {
      _scheduleScrollToBottom(animated: shouldAutoScrollForSend);
      if (shouldAutoScrollForSend) {
        _pendingScrollAfterSend = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollToBottomVisibility();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _timelineScrollController.removeListener(_handleTimelineScroll);
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasWorkspace =
        (widget.state.selectedWorkspacePath != null &&
            widget.state.selectedWorkspacePath!.isNotEmpty) ||
        widget.state.activeSession != null;
    final shouldShowImplementPlanButton = _shouldShowImplementPlanButton();
    final useMeta = Platform.isMacOS;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(
          LogicalKeyboardKey.keyL,
          meta: useMeta,
          control: !useMeta,
        ): _focusComposer,
        SingleActivator(
          LogicalKeyboardKey.keyP,
          shift: true,
          meta: useMeta,
          control: !useMeta,
        ): _togglePlanMode,
        SingleActivator(
          LogicalKeyboardKey.keyY,
          shift: true,
          meta: useMeta,
          control: !useMeta,
        ): _toggleFullAccess,
        SingleActivator(
          LogicalKeyboardKey.keyM,
          shift: true,
          meta: useMeta,
          control: !useMeta,
        ): _openModelDropdown,
        SingleActivator(
          LogicalKeyboardKey.keyT,
          meta: useMeta,
          control: !useMeta,
        ): _openReasoningDropdown,
        const SingleActivator(LogicalKeyboardKey.tab, shift: true):
            _togglePlanMode,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ChatTimelineList(
                      state: widget.state,
                      expandedWorkedTurns: _expandedWorkedTurns,
                      onToggleWorkedTurn: _toggleWorkedTurn,
                      controller: _timelineScrollController,
                      markdownEnabled: widget.isMarkdownEnabled,
                      onMarkdownModeChanged: widget.onMarkdownModeChanged,
                      contentMaxWidth: _timelineContentMaxWidth,
                      showImplementPlanButton: shouldShowImplementPlanButton,
                      onImplementPlanPressed: _onImplementPlanPressed,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: AleraTokens.space12,
                      ),
                      child: IgnorePointer(
                        ignoring: !_showScrollToBottom,
                        child: AnimatedOpacity(
                          duration: AleraTokens.durationFast,
                          opacity: _showScrollToBottom ? 1 : 0,
                          child: IconButton(
                            key: const ValueKey<String>(
                              'scroll-to-bottom-button',
                            ),
                            onPressed: _showScrollToBottom
                                ? () => _scheduleScrollToBottom(animated: true)
                                : null,
                            mouseCursor: SystemMouseCursors.click,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              backgroundColor: AleraTokens.bg,
                              foregroundColor: AleraTokens.foreground,
                              side: const BorderSide(
                                color: AleraTokens.border,
                                width: 1,
                              ),
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.arrow_downward, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.state.pendingApprovals.isNotEmpty)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space12,
                    ),
                    child: Column(
                      children: widget.state.pendingApprovals
                          .map((approval) {
                            return ApprovalCard(
                              approval: approval,
                              onApprove: () => widget.onApproveRequest(
                                approval.requestId,
                                forSession: false,
                              ),
                              onApproveForSession: () =>
                                  widget.onApproveRequest(
                                    approval.requestId,
                                    forSession: true,
                                  ),
                              onDecline: () =>
                                  widget.onDeclineRequest(approval.requestId),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                ),
              ),
            if (widget.state.pendingUserInput != null)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space12,
                    ),
                    child: UserInputCard(
                      pendingUserInput: widget.state.pendingUserInput!,
                      onSubmit: widget.onSubmitUserInput,
                      onDismiss: widget.onDismissUserInput,
                    ),
                  ),
                ),
              ),
            if (widget.state.pendingMessages.isNotEmpty)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: MessageQueueBar(
                    messages: widget.state.pendingMessages,
                    onRemove: widget.onRemoveFromQueue,
                    onEdit: _handleEditQueuedMessage,
                    onSteer: widget.onSteerQueuedMessage,
                    canSteer: widget.isTurnRunning && !widget.isInterrupting,
                  ),
                ),
              ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Composer(
                  key: _composerKey,
                  controller: _inputController,
                  textFieldEnabled: hasWorkspace,
                  canSend: hasWorkspace && !widget.isInterrupting,
                  canStop:
                      widget.state.activeSession != null &&
                      widget.isTurnRunning &&
                      !widget.state.isBusy,
                  canChangeModel: hasWorkspace,
                  isBusy: widget.state.isBusy,
                  isInterrupting: widget.isInterrupting,
                  activeModelId: widget.state.activeModelId,
                  availableModels: widget.state.availableModels,
                  onModelChanged: widget.onModelChanged,
                  activeReasoningEffort: widget.activeReasoningEffort,
                  supportedReasoningEfforts: widget.supportedReasoningEfforts,
                  onReasoningEffortChanged: widget.onReasoningEffortChanged,
                  hintText: widget.state.activeSession != null
                      ? 'Ask for follow-up changes'
                      : 'Ask Alera anything, @ to add files, / for commands',
                  onSend: _sendInput,
                  onInterrupt: widget.onInterruptTurn,
                  attachments: widget.state.composerAttachments,
                  draftItems: widget.state.composerDraftItems,
                  availableCommands: widget.state.availableCommands,
                  onAddAttachment: hasWorkspace ? widget.onAddAttachment : null,
                  onPasteImage: hasWorkspace ? widget.onPasteImage : null,
                  onRemoveAttachment: widget.onRemoveAttachment,
                  onRemoveDraftItem: hasWorkspace ? _removeDraftItem : null,
                  onImmediateCommandSelected: hasWorkspace
                      ? _handleImmediateCommandSelected
                      : null,
                  workspacePath: widget.state.selectedWorkspacePath,
                  planModeEnabled: widget.state.planModeEnabled,
                  onPlanModeToggled: hasWorkspace
                      ? widget.onPlanModeToggled
                      : null,
                  permissionMode: widget.state.permissionMode,
                  onPermissionModeSelected: hasWorkspace
                      ? widget.onPermissionModeSelected
                      : null,
                  contextUsage: widget.state.contextUsage,
                  onCompact: widget.onCompact,
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: RawLog(
                  state: widget.state,
                  expanded: widget.rawLogExpanded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (_handleLocalSlashCommandSubmission(text)) {
      return;
    }
    _inputController.clear();
    _pendingScrollAfterSend = true;
    _scheduleScrollToBottom(animated: true);
    widget.onSendInput(text);
  }

  bool _handleLocalSlashCommandSubmission(String text) {
    final parsed = parseSlashCommand(text);
    if (parsed == null || parsed.hasArgs || parsed.remainingText.isNotEmpty) {
      return false;
    }
    final command = _commandRegistry.findExact(
      widget.state.availableCommands,
      parsed.name,
    );
    if (command == null || !_isLocalComposerCommand(command)) {
      return false;
    }
    _inputController.clear();
    unawaited(_runImmediateCommand(command));
    return true;
  }

  bool _isLocalComposerCommand(AleraCommand command) {
    return switch (command.builtinId) {
      BuiltinCommandId.model => true,
      BuiltinCommandId.permissions => true,
      BuiltinCommandId.skills => true,
      BuiltinCommandId.apps => true,
      BuiltinCommandId.mention => true,
      BuiltinCommandId.review => true,
      BuiltinCommandId.status => true,
      _ => false,
    };
  }

  void _handleImmediateCommandSelected(AleraCommand command) {
    unawaited(_runImmediateCommand(command));
  }

  Future<void> _runImmediateCommand(AleraCommand command) async {
    switch (command.builtinId) {
      case BuiltinCommandId.model:
        _openModelDropdown();
        return;
      case BuiltinCommandId.permissions:
        _composerKey.currentState?.openPermissionDropdown();
        return;
      case BuiltinCommandId.mention:
        _insertTextAtCursor('@');
        return;
      case BuiltinCommandId.review:
        await _openReviewFlow();
        return;
      case BuiltinCommandId.skills:
        await _pickSkill();
        return;
      case BuiltinCommandId.apps:
        await _pickApp();
        return;
      case BuiltinCommandId.status:
        await _showStatusDialog();
        return;
      default:
        widget.onSendInput('/${command.name}');
        return;
    }
  }

  void _insertTextAtCursor(String text) {
    final value = _inputController.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final nextText = value.text.replaceRange(start, end, text);
    _inputController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
    _composerKey.currentState?.requestFocus();
  }

  void _appendTokenText(String token) {
    final current = _inputController.text;
    final needsLeadingSpace = current.isNotEmpty && !current.endsWith(' ');
    final prefix = needsLeadingSpace ? ' ' : '';
    _insertTextAtCursor('$prefix$token ');
  }

  void _removeDraftItem(String id) {
    final callback = widget.onRemoveDraftItem;
    if (callback == null) {
      return;
    }
    final item = widget.state.composerDraftItems.where((candidate) {
      return candidate.id == id;
    }).firstOrNull;
    callback(id);
    if (item == null ||
        item.kind != ComposerDraftItemKind.mention ||
        item.tokenText == null ||
        item.tokenText!.isEmpty) {
      return;
    }
    final text = _inputController.text;
    final token = item.tokenText!;
    final updated = text.replaceFirst('$token ', '').replaceFirst(token, '');
    if (updated == text) {
      return;
    }
    _inputController.value = _inputController.value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _pickSkill() async {
    final loadSkills = widget.onListSkills;
    final addDraftItem = widget.onAddDraftItem;
    if (loadSkills == null || addDraftItem == null) {
      return;
    }
    final skills = await loadSkills();
    if (!mounted || skills.isEmpty) {
      return;
    }
    final selected = await showDialog<CodexSkillMetadata>(
      context: context,
      builder: (context) => _FilterableSelectionDialog<CodexSkillMetadata>(
        title: 'Select a skill',
        items: skills,
        searchHintText: 'Filter skills',
        searchFieldRadius: AleraTokens.radiusPill,
        searchText: (skill) =>
            '${skill.name} ${skill.description} ${skill.shortDescription ?? ""}',
        itemBuilder: (skill) => _SelectionRow(
          title: skill.name,
          subtitle: skill.shortDescription?.trim().isNotEmpty == true
              ? skill.shortDescription!
              : skill.description,
          trailing: skill.scope,
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    addDraftItem(
      ComposerDraftItem(
        id: 'skill-${selected.path}',
        kind: ComposerDraftItemKind.skill,
        name: selected.name,
        path: selected.path,
      ),
    );
    _composerKey.currentState?.requestFocus();
  }

  Future<void> _pickApp() async {
    final loadApps = widget.onListApps;
    final addDraftItem = widget.onAddDraftItem;
    if (loadApps == null || addDraftItem == null) {
      return;
    }
    final apps = await loadApps();
    if (!mounted || apps.isEmpty) {
      return;
    }
    final selected = await showDialog<CodexAppInfo>(
      context: context,
      builder: (context) => _FilterableSelectionDialog<CodexAppInfo>(
        title: 'Select an app',
        items: apps,
        searchHintText: 'Filter apps',
        searchText: (app) => '${app.id} ${app.name} ${app.description ?? ""}',
        itemBuilder: (app) => _SelectionRow(
          title: app.id,
          subtitle: app.description ?? app.name,
          trailing: app.name,
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    final token = '\$${selected.id}';
    addDraftItem(
      ComposerDraftItem(
        id: 'app-${selected.id}',
        kind: ComposerDraftItemKind.mention,
        name: selected.id,
        path: 'app://${selected.id}',
        tokenText: token,
      ),
    );
    _appendTokenText(token);
  }

  Future<void> _showStatusDialog() {
    final session = widget.state.activeSession;
    final facts = <_StatusFact>[
      _StatusFact(
        label: 'Workspace',
        value: widget.state.selectedWorkspacePath ?? 'none',
      ),
      _StatusFact(label: 'Session', value: session?.title ?? 'new chat'),
      _StatusFact(label: 'Model', value: widget.state.activeModelId),
      _StatusFact(
        label: 'Reasoning',
        value: widget.state.activeReasoningEffort,
      ),
      _StatusFact(
        label: 'Plan mode',
        value: widget.state.planModeEnabled ? 'On' : 'Off',
      ),
      _StatusFact(
        label: 'Permissions',
        value: widget.state.permissionMode == PermissionMode.fullAccess
            ? 'Full access'
            : 'Ask first',
      ),
      _StatusFact(
        label: 'Queued messages',
        value: widget.state.pendingMessages.length.toString(),
      ),
    ];
    return showDialog<void>(
      context: context,
      builder: (context) => _StatusDialog(facts: facts),
    );
  }

  Future<void> _openReviewFlow() async {
    final callback = widget.onStartReviewFromPreset;
    if (callback == null) {
      return;
    }
    final preset = await showDialog<ReviewPresetSelection>(
      context: context,
      builder: (context) => _FilterableSelectionDialog<ReviewPresetSelection>(
        title: 'Select a review preset',
        items: ReviewPresetSelection.values,
        searchHintText: 'Filter presets',
        searchFieldRadius: AleraTokens.radiusPill,
        searchText: (preset) => '${preset.title} ${preset.description}',
        itemBuilder: (preset) =>
            _SelectionRow(title: preset.title, subtitle: preset.description),
      ),
    );
    if (!mounted || preset == null) {
      return;
    }

    switch (preset) {
      case ReviewPresetSelection.uncommittedChanges:
        await callback(ReviewPresetSelection.uncommittedChanges);
        return;
      case ReviewPresetSelection.baseBranch:
        final loadBranches = widget.onListReviewBranches;
        if (loadBranches == null) {
          return;
        }
        final branches = await loadBranches();
        if (!mounted || branches.isEmpty) {
          return;
        }
        final selectedBranch = await showDialog<String>(
          context: context,
          builder: (context) => _FilterableSelectionDialog<String>(
            title: 'Select a base branch',
            items: branches,
            searchHintText: 'Filter branches',
            searchFieldRadius: AleraTokens.radiusPill,
            searchText: (branch) => branch,
            itemBuilder: (branch) => _SelectionRow(
              title: branch,
              subtitle: 'Review against $branch',
            ),
          ),
        );
        if (selectedBranch == null) {
          return;
        }
        await callback(ReviewPresetSelection.baseBranch, value: selectedBranch);
        return;
      case ReviewPresetSelection.commit:
        final commit = await showDialog<String>(
          context: context,
          builder: (context) => const _TextEntryDialog(
            title: 'Review a commit',
            hintText: 'Enter a commit SHA or ref',
            submitLabel: 'Review commit',
          ),
        );
        if (commit == null || commit.trim().isEmpty) {
          return;
        }
        await callback(ReviewPresetSelection.commit, value: commit.trim());
        return;
      case ReviewPresetSelection.customInstructions:
        final instructions = await showDialog<String>(
          context: context,
          builder: (context) => const _TextEntryDialog(
            title: 'Custom review instructions',
            hintText: 'Describe what the review should focus on',
            submitLabel: 'Start review',
            minLines: 5,
            maxLines: 10,
          ),
        );
        if (instructions == null || instructions.trim().isEmpty) {
          return;
        }
        await callback(
          ReviewPresetSelection.customInstructions,
          value: instructions.trim(),
        );
        return;
    }
  }

  void _handleEditQueuedMessage(PendingMessage message) {
    // Notify controller that editing has started.
    widget.onStartEditingPendingMessage(message.id);
    showDialog<void>(
      context: context,
      builder: (context) => QueueMessageEditDialog(
        message: message,
        workspacePath: widget.state.selectedWorkspacePath,
        onSave: (result) {
          widget.onUpdatePendingMessage(
            message.id,
            result.text,
            result.attachments,
          );
          widget.onFinishEditingPendingMessage();
        },
        onDelete: () {
          widget.onDeletePendingMessage(message.id);
          // onDeletePendingMessage calls removeFromQueue which handles editing state.
        },
      ),
    ).then((_) {
      // If dialog is dismissed without saving (e.g., via Escape key),
      // we still need to clear the editing state.
      if (widget.state.editingPendingMessageId == message.id) {
        widget.onFinishEditingPendingMessage();
      }
    });
  }

  void _focusComposer() {
    _composerKey.currentState?.requestFocus();
  }

  void _togglePlanMode() {
    widget.onPlanModeToggled();
  }

  void _toggleFullAccess() {
    widget.onPermissionModeToggled();
  }

  void _openModelDropdown() {
    _composerKey.currentState?.openModelsDropdown();
  }

  void _openReasoningDropdown() {
    _composerKey.currentState?.openReasoningDropdown();
  }

  void _onImplementPlanPressed() {
    unawaited(widget.onImplementPlanPressed());
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

  bool _hasNonUserTimelineChanges(
    List<TimelineCell> previous,
    List<TimelineCell> next,
  ) {
    final previousById = <String, TimelineCell>{
      for (final cell in previous) cell.id: cell,
    };
    for (final cell in next) {
      final old = previousById.remove(cell.id);
      if (old == null) {
        if (cell.kind != TimelineCellKind.userMessage) {
          return true;
        }
        continue;
      }
      if (_hasCellChanged(old, cell) &&
          cell.kind != TimelineCellKind.userMessage) {
        return true;
      }
    }
    for (final removed in previousById.values) {
      if (removed.kind != TimelineCellKind.userMessage) {
        return true;
      }
    }
    return false;
  }

  bool _hasCellChanged(TimelineCell previous, TimelineCell next) {
    return previous.status != next.status ||
        previous.updatedAt != next.updatedAt ||
        previous.isStreaming != next.isStreaming ||
        previous.isCollapsed != next.isCollapsed ||
        previous.title != next.title ||
        previous.subtitle != next.subtitle ||
        previous.markdownText != next.markdownText ||
        previous.detailsText != next.detailsText;
  }

  bool _shouldShowImplementPlanButton() {
    if (widget.state.pendingMessages.isNotEmpty) {
      return false;
    }
    var lastPlanIndex = -1;
    var lastUserMessageIndex = -1;
    final cells = widget.state.timelineCells;
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (cell.kind == TimelineCellKind.plan) {
        lastPlanIndex = i;
      } else if (cell.kind == TimelineCellKind.userMessage) {
        lastUserMessageIndex = i;
      }
    }
    return lastPlanIndex != -1 && lastPlanIndex > lastUserMessageIndex;
  }

  void _handleTimelineScroll() {
    _updateScrollToBottomVisibility();
  }

  bool _isAtBottom({required double tolerancePx}) {
    if (!_timelineScrollController.hasClients) {
      return true;
    }
    final position = _timelineScrollController.position;
    final distanceToBottom = (position.maxScrollExtent - position.pixels).clamp(
      0.0,
      double.infinity,
    );
    return distanceToBottom <= tolerancePx;
  }

  void _updateScrollToBottomVisibility() {
    if (!mounted) {
      return;
    }
    if (!_timelineScrollController.hasClients) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }
    final shouldShow = !_isAtBottom(tolerancePx: _bottomTolerancePx);
    if (shouldShow == _showScrollToBottom) {
      return;
    }
    setState(() {
      _showScrollToBottom = shouldShow;
    });
  }

  void _scheduleScrollToBottom({bool animated = false}) {
    _scrollToBottomIfPossible(animated: animated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomIfPossible(animated: animated);
    });
  }

  bool _scrollToBottomIfPossible({required bool animated}) {
    if (!mounted || !_timelineScrollController.hasClients) {
      return false;
    }
    final target = _timelineScrollController.position.maxScrollExtent;
    if (animated) {
      _timelineScrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(_updateScrollToBottomVisibility);
      return true;
    }
    _timelineScrollController.jumpTo(target);
    _updateScrollToBottomVisibility();
    return true;
  }
}

class _FilterableSelectionDialog<T> extends StatefulWidget {
  const _FilterableSelectionDialog({
    required this.title,
    required this.items,
    required this.searchText,
    required this.itemBuilder,
    this.searchHintText = 'Filter',
    this.searchFieldRadius = AleraTokens.radiusMd,
  });

  final String title;
  final List<T> items;
  final String Function(T item) searchText;
  final Widget Function(T item) itemBuilder;
  final String searchHintText;
  final double searchFieldRadius;

  @override
  State<_FilterableSelectionDialog<T>> createState() =>
      _FilterableSelectionDialogState<T>();
}

class _FilterableSelectionDialogState<T>
    extends State<_FilterableSelectionDialog<T>> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final filtered = widget.items
        .where((item) {
          if (query.isEmpty) {
            return true;
          }
          return widget.searchText(item).toLowerCase().contains(query);
        })
        .toList(growable: false);

    return Dialog(
      backgroundColor: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
        side: const BorderSide(color: AleraTokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space16,
                AleraTokens.space16,
                AleraTokens.space16,
                AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('filter-dialog-close-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: AleraTokens.foregroundMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusPill,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space16,
                0,
                AleraTokens.space16,
                AleraTokens.space12,
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.searchHintText,
                  filled: true,
                  fillColor: AleraTokens.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                    vertical: AleraTokens.space12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      widget.searchFieldRadius,
                    ),
                    borderSide: const BorderSide(color: AleraTokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      widget.searchFieldRadius,
                    ),
                    borderSide: const BorderSide(color: AleraTokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      widget.searchFieldRadius,
                    ),
                    borderSide: const BorderSide(color: AleraTokens.info),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AleraTokens.space16),
                        child: Text(
                          'No results',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AleraTokens.foregroundMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (index > 0)
                              const Divider(
                                height: 1,
                                color: AleraTokens.borderSubtle,
                              ),
                            InkWell(
                              onTap: () => Navigator.of(context).pop(item),
                              mouseCursor: SystemMouseCursors.click,
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  AleraTokens.space12,
                                ),
                                child: widget.itemBuilder(item),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDialog extends StatelessWidget {
  const _StatusDialog({required this.facts});

  final List<_StatusFact> facts;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
        side: const BorderSide(color: AleraTokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Current status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('status-dialog-close-button'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: AleraTokens.foregroundMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusPill,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space12),
              Container(
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  border: Border.all(color: AleraTokens.borderSubtle),
                ),
                child: Column(
                  children: facts
                      .map((fact) {
                        final isLast = identical(fact, facts.last);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AleraTokens.space12,
                            vertical: AleraTokens.space12,
                          ),
                          decoration: BoxDecoration(
                            border: isLast
                                ? null
                                : const Border(
                                    bottom: BorderSide(
                                      color: AleraTokens.borderSubtle,
                                    ),
                                  ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(
                                width: 120,
                                child: Text(
                                  fact.label,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AleraTokens.foregroundFaint,
                                      ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  fact.value,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.title,
    required this.hintText,
    required this.submitLabel,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String title;
  final String hintText;
  final String submitLabel;
  final int minLines;
  final int maxLines;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
        side: const BorderSide(color: AleraTokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AleraTokens.space12),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: AleraTokens.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    borderSide: const BorderSide(color: AleraTokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    borderSide: const BorderSide(color: AleraTokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    borderSide: const BorderSide(color: AleraTokens.info),
                  ),
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text.trim()),
                    child: Text(widget.submitLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AleraTokens.space4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null && trailing!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            child: Text(
              trailing!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusFact {
  const _StatusFact({required this.label, required this.value});

  final String label;
  final String value;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
