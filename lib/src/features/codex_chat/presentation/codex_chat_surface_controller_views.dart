part of 'codex_chat_surface.dart';

class _CodexControllerTimeline extends ConsumerWidget {
  const _CodexControllerTimeline({
    required this.tabId,
    required this.workspacePath,
    required this.fallbackTitle,
    required this.showRawLogs,
    required this.timeline,
    required this.timelineKey,
    required this.loadingEarlier,
    required this.planDecisionRevision,
    required this.onOpenAttachment,
  });

  final String tabId;
  final String workspacePath;
  final String fallbackTitle;
  final bool showRawLogs;
  final ScrollController timeline;
  final GlobalKey<_CodexTimelineState> timelineKey;
  final bool loadingEarlier;
  final ValueNotifier<int> planDecisionRevision;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      codexChatControllerProvider(tabId).select(_CodexTimelineViewState.from),
    );
    final controller = ref.read(codexChatControllerProvider(tabId).notifier);
    if (view.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (view.error != null &&
        view.snapshot.timelineCells.isEmpty &&
        view.snapshot.events.isEmpty) {
      return _CodexFailure(message: view.error!, onRetry: controller.retry);
    }
    return Column(
      children: <Widget>[
        if (view.historyNextCursor != null)
          Center(
            child: TextButton.icon(
              onPressed: () =>
                  controller.loadHistory(cursor: view.historyNextCursor),
              icon: const Icon(AleraIcons.chevronUp, size: AleraTokens.iconSm),
              label: const Text('Load Earlier Messages'),
            ),
          ),
        Expanded(
          child: _CodexTimeline(
            key: timelineKey,
            snapshot: view.snapshot,
            workspacePath: view.activeCwd ?? workspacePath,
            title: view.snapshot.title ?? fallbackTitle,
            showRawLogs: showRawLogs,
            timeline: timeline,
            loadingEarlier: loadingEarlier,
            planDecisionRevision: planDecisionRevision,
            onOpenAttachment: onOpenAttachment,
            onApproval: controller.respondApproval,
            onElicitation: controller.respondElicitation,
            onReject: controller.rejectRequest,
          ),
        ),
      ],
    );
  }
}

class _CodexControllerFooter extends ConsumerWidget {
  const _CodexControllerFooter({
    required this.tabId,
    required this.composerController,
    required this.composerFocus,
    required this.attachments,
    required this.draftItems,
    required this.savedPrompts,
    required this.workspacePath,
    required this.workspaceFiles,
    required this.onEditQueued,
    required this.onDraftItemSelected,
    required this.onCommand,
    required this.onSend,
    required this.onAddAttachment,
    required this.onPaste,
    required this.onDropAttachments,
    required this.onRemoveAttachment,
    required this.onOpenAttachment,
    required this.onRemoveDraftItem,
    required this.onSubmitQuestions,
    required this.onPlanInteraction,
    required this.onImplementPlan,
    required this.onDeclinePlan,
    required this.onRefinePlan,
  });

  final String tabId;
  final TextEditingController composerController;
  final FocusNode composerFocus;
  final List<CodexInputAttachment> attachments;
  final List<CodexDraftItem> draftItems;
  final List<native.CodexSavedPrompt> savedPrompts;
  final String workspacePath;
  final WorkspaceFileService workspaceFiles;
  final void Function(int index, CodexQueuedMessage message) onEditQueued;
  final ValueChanged<CodexDraftItem> onDraftItemSelected;
  final void Function(CodexChatState state, CodexComposerCommand command)
  onCommand;
  final VoidCallback onSend;
  final Future<void> Function() onAddAttachment;
  final Future<void> Function() onPaste;
  final Future<void> Function(
    Iterable<String> paths, {
    CodexInputAttachmentOrigin origin,
    String? tokenText,
    int? tokenStart,
  })
  onDropAttachments;
  final ValueChanged<CodexInputAttachment> onRemoveAttachment;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;
  final ValueChanged<CodexDraftItem> onRemoveDraftItem;
  final Future<void> Function(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  )
  onSubmitQuestions;
  final VoidCallback onPlanInteraction;
  final Future<void> Function() onImplementPlan;
  final Future<void> Function() onDeclinePlan;
  final Future<void> Function(String value) onRefinePlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      codexChatControllerProvider(tabId).select(_CodexFooterViewState.from),
    );
    final state = view.state;
    final controller = ref.read(codexChatControllerProvider(tabId).notifier);
    final showQuestionDock =
        state.recovery == null &&
        (view.pendingQuestions.isNotEmpty || view.showLocalPlanQuestion);
    final showComposer =
        !showQuestionDock ||
        (view.pendingQuestions.isNotEmpty && !view.hasBlockingQuestion);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.error != null)
          _CodexInlineError(message: state.error!, onRetry: controller.retry),
        if (state.queuedMessages.isNotEmpty)
          _CodexQueueBar(
            messages: state.queuedMessages,
            canSteer: controller.canSteer,
            onRemove: controller.removeQueuedMessage,
            onEdit: onEditQueued,
            onSteer: (index, message) async {
              if (!controller.canSteer) return;
              final sent = await controller.steer(
                message.text,
                attachments: message.attachments,
                draftItems: message.draftItems,
              );
              if (sent) controller.removeQueuedMessage(index);
            },
          ),
        if (view.planProgress != null)
          _CodexPlanProgressDock(progress: view.planProgress!),
        if (state.recovery != null)
          Flexible(
            fit: FlexFit.loose,
            child: _CodexRecoveryQuestionDock(
              key: ValueKey<(String, String?)>((tabId, controller.threadId)),
              message: state.recovery!.message,
              onContinue: controller.recoverThread,
            ),
          ),
        if (showQuestionDock)
          Flexible(
            fit: FlexFit.loose,
            child: view.pendingQuestions.isNotEmpty
                ? _CodexPendingQuestionQueue(
                    key: ValueKey<(String, String?)>((
                      tabId,
                      controller.threadId,
                    )),
                    tabId: tabId,
                    requests: view.pendingQuestions,
                    builder: (request, draft) => _CodexQuestionDock(
                      state: state,
                      showModelSelector: request.isImplementPlanQuestion,
                      onModelChanged: controller.setModel,
                      onReasoningChanged: controller.setReasoning,
                      onSpeedChanged: controller.setSpeed,
                      onCollaborationChanged: controller.setCollaborationMode,
                      card: _CodexQuestionCard(
                        key: ValueKey<String>(
                          _codexQuestionCardStateKey(tabId, request),
                        ),
                        request: request,
                        draft: draft,
                        onQuestion: onSubmitQuestions,
                        onInteraction: (request) => unawaited(
                          controller.snoozeQuestionAutoResolution(request),
                        ),
                      ),
                    ),
                  )
                : _CodexQuestionDock(
                    state: state,
                    showModelSelector: true,
                    onModelChanged: controller.setModel,
                    onReasoningChanged: controller.setReasoning,
                    onSpeedChanged: controller.setSpeed,
                    onCollaborationChanged: controller.setCollaborationMode,
                    card: _CodexPlanQuestionCard(
                      key: ValueKey<(String, String?)>((
                        tabId,
                        view.actionablePlanId,
                      )),
                      onInteraction: onPlanInteraction,
                      onImplement: onImplementPlan,
                      onDecline: onDeclinePlan,
                      onRefine: onRefinePlan,
                    ),
                  ),
          ),
        if (showComposer)
          _CodexComposer(
            controller: composerController,
            focusNode: composerFocus,
            busy: state.busy,
            interrupting: state.interrupting,
            mcpInitializing: view.mcpInitializing,
            blockedMessage: state.recovery == null
                ? null
                : 'Continue in a new thread to resume.',
            attachments: attachments,
            draftItems: draftItems,
            savedPrompts: savedPrompts,
            state: state,
            promptHistory: state.snapshot.promptHistory,
            workspacePath: state.activeCwd ?? workspacePath,
            workspaceFiles: workspaceFiles,
            onModelChanged: controller.setModel,
            onReasoningChanged: controller.setReasoning,
            onSpeedChanged: controller.setSpeed,
            onPermissionChanged: controller.setPermissionMode,
            onPlanChanged: controller.setPlanMode,
            onCollaborationChanged: controller.setCollaborationMode,
            onDraftItemSelected: onDraftItemSelected,
            onCommand: (command) => onCommand(state, command),
            onSend: onSend,
            onStop: controller.stop,
            onAddAttachment: onAddAttachment,
            onPaste: onPaste,
            onDropAttachments: onDropAttachments,
            onRemoveAttachment: onRemoveAttachment,
            onOpenAttachment: onOpenAttachment,
            onRemoveDraftItem: onRemoveDraftItem,
          ),
      ],
    );
  }
}
