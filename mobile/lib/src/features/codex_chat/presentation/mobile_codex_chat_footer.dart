part of 'mobile_codex_chat_screen.dart';

Widget _buildMobileCodexFooter(
  _MobileCodexChatScreenState owner,
  BuildContext context,
  MobileCodexState state,
  MobileCodexController controller, {
  required double availableHeight,
}) {
  final progress = _MobilePlanProgress.fromCells(
    state.timelineCells,
    activeTurnId: state.activeTurnId,
  );
  Widget buildQueue() =>
      _MobileQueueBar(messages: state.queuedMessages, controller: controller);
  Widget buildGoal() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
    child: _MobileCodexGoalBar(
      goal: state.goal!,
      turnActive: state.activeTurnId != null,
      onEdit: () async {
        final objective = await _showMobileCodexGoalEditor(
          context,
          initialObjective: state.goal!.objective,
        );
        if (objective != null) await controller.editGoal(objective);
      },
      onPauseResume: state.goal!.status.canPause
          ? () => unawaited(
              controller.updateGoalStatus(MobileCodexGoalStatus.paused),
            )
          : state.goal!.status.canResume
          ? () => unawaited(
              controller.updateGoalStatus(MobileCodexGoalStatus.active),
            )
          : null,
      onClear: () => unawaited(controller.clearGoal()),
    ),
  );
  Widget buildComposer() => _MobileComposer(
    controller: owner._composer,
    focusNode: owner._composerFocus,
    chatController: controller,
    workspaceId: owner.widget.workspaceId,
    hostId: owner.widget.hostId,
    tabId: owner.widget.tabId,
    state: state,
    attachments: owner._attachments,
    busy: state.busy,
    interrupting: state.interrupting,
    blockedMessage: state.recovery == null
        ? null
        : 'Continue in a new thread to resume.',
    onAttach: () =>
        owner._showAttachmentPicker(controller, cwd: state.activeCwd),
    onAddAttachment: (attachment) =>
        owner._setDraftState(() => owner._attachments.add(attachment)),
    onCatalogSelection: (selection) => owner._setDraftState(() {
      final identity = _mobileCatalogSelectionIdentity(selection);
      owner._catalogSelections.removeWhere(
        (existing) => _mobileCatalogSelectionIdentity(existing) == identity,
      );
      owner._catalogSelections.add(selection);
    }),
    onRemoveAttachment: owner._removeAttachment,
    onSend: () => owner._send(controller),
    onSteer: () => owner._steer(controller),
    onStop: controller.stop,
    canAttach:
        controller.supportsImageUpload ||
        controller.supportsFileUpload ||
        controller.supportsWorkspaceFiles,
    onModel: controller.setModel,
    onReasoning: controller.setReasoning,
    onSpeed: controller.setSpeed,
    onPermission: controller.setPermissionMode,
    onPlan: controller.setPlanMode,
    onCollaboration: controller.setCollaborationMode,
    onCompact: controller.compact,
    onReview: () => _showMobileReviewDialog(context, controller),
    onRename: () => _showMobileRenameDialog(context, controller, state.title),
    onResume: () => owner._resumeThread(context, controller, state),
    onNew: controller.newThread,
    onClear: controller.clearThread,
    supportsSessions: controller.supportsSessions,
    supportsTurnPolicy: controller.supportsTurnPolicy,
  );
  Widget buildUpperContent() => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (state.error != null)
        MaterialBanner(
          content: Text(state.error!),
          leading: const Icon(Icons.error_outline),
          actions: <Widget>[
            TextButton(
              onPressed: () => owner.ref.invalidate(
                mobileCodexControllerProvider(
                  owner.widget.hostId,
                  owner.widget.tabId,
                ),
              ),
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: controller.clearError,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      if (state.recovery != null)
        MaterialBanner(
          key: const ValueKey<String>('mobile-codex-thread-recovery'),
          content: Text(
            '${state.recovery!.message} Earlier messages remain visible, but they are not part of the new model context.',
          ),
          leading: const Icon(Icons.warning_amber_outlined),
          actions: <Widget>[
            TextButton(
              onPressed: () => unawaited(controller.recoverThread()),
              child: const Text('Continue In New Thread'),
            ),
          ],
        ),
      if (owner._showScrollToBottom)
        IconButton.outlined(
          tooltip: 'Scroll To Bottom',
          onPressed: owner._scrollToBottom,
          icon: const Icon(Icons.arrow_downward),
        ),
      if (progress != null) _MobilePlanProgressBadge(progress: progress),
      if (state.recovery == null &&
          (state.pendingRequests.isNotEmpty ||
              state.planMode && state.shouldShowImplementPlan))
        _MobileInteractionDock(state: state, controller: controller),
      if (state.queueState['editOperation'] case final Map operation)
        AleraHistoryEditStatus(
          phase: operation['phase'].toString(),
          error:
              (operation['payload'] as Map?)?['lastError']?.toString() ??
              (operation['result'] as Map?)?['error']?.toString(),
          onRetry: () => unawaited(
            controller.retryHistoryEdit(operation['id'].toString()),
          ),
        ),
      if (state.queuedMessages.isNotEmpty || state.queuePaused) buildQueue(),
      if (controller.supportsGoals && state.goal != null) buildGoal(),
    ],
  );
  final compact = availableHeight < AleraTokens.codexChatFooterMaxHeight;
  if (compact) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[buildUpperContent(), buildComposer()],
        ),
      ),
    );
  }
  return ConstrainedBox(
    constraints: const BoxConstraints(
      maxHeight: AleraTokens.codexChatFooterMaxHeight,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(child: buildUpperContent()),
        ),
        buildComposer(),
      ],
    ),
  );
}

String _mobileCatalogSelectionIdentity(Map<String, Object?> selection) =>
    '${selection['type']}\u{0}${selection['path']}\u{0}${selection['name']}';
