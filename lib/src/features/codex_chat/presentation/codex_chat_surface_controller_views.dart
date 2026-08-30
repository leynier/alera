part of 'codex_chat_surface.dart';

class const _CodexControllerTimeline({
  required final String tabId,
  required final String workspacePath,
  required final String fallbackTitle,
  required final bool showRawLogs,
  required final ScrollController timeline,
  required final GlobalKey<_CodexTimelineState> timelineKey,
  required final bool loadingEarlier,
  required final ValueNotifier<int> planDecisionRevision,
  required final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment,
}) extends ConsumerWidget {
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

class const _CodexControllerFooter({
  required final String tabId,
  required final TextEditingController composerController,
  required final FocusNode composerFocus,
  required final List<CodexInputAttachment> attachments,
  required final List<CodexDraftItem> draftItems,
  required final List<native.CodexSavedPrompt> savedPrompts,
  required final String workspacePath,
  required final String workspaceId,
  required final WorkspaceFileService workspaceFiles,
  required final void Function(int index, CodexQueuedMessage message)
  onEditQueued,
  required final ValueChanged<CodexDraftItem> onDraftItemSelected,
  required final void Function(
    CodexChatState state,
    CodexComposerCommand command,
  )
  onCommand,
  required final VoidCallback onSend,
  required final Future<void> Function() onAddAttachment,
  required final Future<void> Function() onPaste,
  required final Future<void> Function(
    Iterable<String> paths, {
    CodexInputAttachmentOrigin origin,
    String? tokenText,
    int? tokenStart,
  })
  onDropAttachments,
  required final ValueChanged<CodexInputAttachment> onRemoveAttachment,
  required final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment,
  required final ValueChanged<CodexDraftItem> onRemoveDraftItem,
  required final Future<void> Function(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  )
  onSubmitQuestions,
  required final VoidCallback onPlanInteraction,
  required final Future<void> Function() onImplementPlan,
  required final Future<void> Function() onDeclinePlan,
  required final Future<void> Function(String value) onRefinePlan,
}) extends ConsumerWidget {
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
    final goal = state.supportsGoals ? state.snapshot.goal : null;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
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
            fit: .loose,
            child: _CodexRecoveryQuestionDock(
              key: ValueKey<(String, String?)>((tabId, controller.threadId)),
              message: state.recovery!.message,
              onContinue: controller.recoverThread,
            ),
          ),
        if (showQuestionDock)
          Flexible(
            fit: .loose,
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
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AleraTokens.codexConversationMaxWidth,
              ),
              child: Stack(
                clipBehavior: .none,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.only(
                      top: goal == null ? 0 : AleraTokens.space32,
                    ),
                    child: _CodexComposer(
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
                      workspaceId: workspaceId,
                      tabId: tabId,
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
                  ),
                  if (goal != null)
                    Positioned(
                      top: 0,
                      left: AleraTokens.space16,
                      right: AleraTokens.space16,
                      child: _CodexGoalBar(
                        goal: goal,
                        turnActive: state.snapshot.activeTurnId != null,
                        onEdit: () async {
                          final objective = await _showCodexGoalEditor(
                            context,
                            initialObjective: goal.objective,
                          );
                          if (objective != null) {
                            await controller.editGoal(objective);
                          }
                        },
                        onPauseResume: goal.status.canPause
                            ? () => unawaited(
                                controller.updateGoalStatus(.paused),
                              )
                            : goal.status.canResume
                            ? () => unawaited(
                                controller.updateGoalStatus(.active),
                              )
                            : null,
                        onClear: () => unawaited(controller.clearGoal()),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
