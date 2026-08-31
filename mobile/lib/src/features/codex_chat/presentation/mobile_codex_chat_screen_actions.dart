part of 'mobile_codex_chat_screen.dart';

// This part keeps stateful session actions separate from the screen layout.
// ignore_for_file: invalid_use_of_protected_member

extension _MobileCodexScreenActions on _MobileCodexChatScreenState {
  Widget _buildFooter(
    BuildContext context,
    MobileCodexState state,
    MobileCodexController controller, {
    required double availableHeight,
  }) => _buildMobileCodexFooter(
    this,
    context,
    state,
    controller,
    availableHeight: availableHeight,
  );

  Future<void> _send(MobileCodexController controller) async {
    final queuedBehindSubmission = _hasPendingMobileSubmission(
      widget.hostId,
      widget.tabId,
    );
    final submissionRevision = _submissionRevision;
    final submissionHostId = widget.hostId;
    final submissionTabId = widget.tabId;
    final submissionThreadGeneration = controller.threadGeneration;
    final state = ref
        .read(mobileCodexControllerProvider(widget.hostId, widget.tabId))
        .value;
    final draftText = _composer.text;
    final attachments = List<Map<String, Object?>>.of(_attachments);
    final catalogSelections = _activeCatalogSelections();
    if (draftText.trim().isEmpty &&
        attachments.isEmpty &&
        catalogSelections.isEmpty) {
      return;
    }
    final submittedDraft = MobileCodexComposerDraft(
      value: _composer.value,
      attachments: attachments,
      catalogSelections: catalogSelections,
    );
    _setDraftState(() {
      _composer.clear();
      _attachments.clear();
      _catalogSelections.clear();
    });
    await _serializeMobileSubmission(
      submissionHostId,
      submissionTabId,
      () async {
        if (!_isCurrentMobileSubmission(
          submissionRevision,
          submissionHostId,
          submissionTabId,
          controller,
          submissionThreadGeneration,
        )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          return;
        }
        final resolvedPrompt = await _expandMobileSavedPrompt(
          controller,
          draftText,
          cwd: state?.activeCwd,
        );
        if (!_isCurrentMobileSubmission(
          submissionRevision,
          submissionHostId,
          submissionTabId,
          controller,
          submissionThreadGeneration,
        )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          return;
        }
        if (resolvedPrompt.failed) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          return;
        }
        final dispatchState = ref
            .read(mobileCodexControllerProvider(widget.hostId, widget.tabId))
            .value;
        if (!resolvedPrompt.expanded &&
            (dispatchState?.busy == true || queuedBehindSubmission) &&
            _isMobileThreadSwitchCommand(
              draftText,
              hasAttachments: attachments.isNotEmpty,
            )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          if (mounted) _composerFocus.requestFocus();
          return;
        }
        if (!resolvedPrompt.expanded &&
            dispatchState != null &&
            _isUnsupportedMobileSessionCommand(
              controller,
              draftText,
              hasAttachments: attachments.isNotEmpty,
            )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          if (mounted) _composerFocus.requestFocus();
          return;
        }
        if (!resolvedPrompt.expanded &&
            dispatchState != null &&
            await _runTypedMobileSessionCommand(
              controller,
              dispatchState,
              draftText,
              hasAttachments: attachments.isNotEmpty,
            )) {
          if (mounted) _composerFocus.requestFocus();
          return;
        }
        if (!_isCurrentMobileSubmission(
          submissionRevision,
          submissionHostId,
          submissionTabId,
          controller,
          submissionThreadGeneration,
        )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          return;
        }
        final accepted = await controller.send(
          resolvedPrompt.text,
          attachments: attachments,
          catalogSelections: catalogSelections,
        );
        if (!accepted) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
        }
      },
    );
  }

  Future<bool> _runTypedMobileSessionCommand(
    MobileCodexController controller,
    MobileCodexState state,
    String draftText, {
    required bool hasAttachments,
  }) async {
    if (hasAttachments) return false;
    final match = RegExp(
      r'^/(goal|rename|new|clear|resume|review|compact)(?:\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(draftText.trim());
    if (match == null) return false;
    final command = match.group(1)!.toLowerCase();
    final argument = match.group(2)?.trim();
    if (command == 'goal') {
      if (!controller.supportsGoals) return false;
      switch (argument?.toLowerCase()) {
        case 'pause':
          await controller.updateGoalStatus(.paused);
        case 'resume':
          await controller.updateGoalStatus(.active);
        case 'clear':
          await controller.clearGoal();
        case 'edit':
          final goal = state.goal;
          if (goal != null) {
            final edited = await _showMobileCodexGoalEditor(
              context,
              initialObjective: goal.objective,
            );
            if (edited != null) await controller.editGoal(edited);
          }
        default:
          if (argument == null || argument.isEmpty) {
            final edited = await _showMobileCodexGoalEditor(
              context,
              initialObjective: state.goal?.objective ?? '',
            );
            if (edited != null) {
              if (state.goal == null) {
                await controller.setGoal(edited, recordUserMessage: true);
              } else {
                await controller.editGoal(edited);
              }
            }
          } else {
            await controller.replaceGoal(argument, recordUserMessage: true);
          }
      }
      return true;
    }
    if (!controller.supportsSessions &&
        const <String>{'new', 'clear', 'resume'}.contains(command)) {
      return true;
    }
    if ((command == 'resume' || command == 'review') &&
        argument != null &&
        argument.isNotEmpty) {
      return false;
    }
    switch (command) {
      case 'rename':
        if (argument == null || argument.isEmpty) {
          await _showMobileRenameDialog(context, controller, state.title);
        } else {
          await controller.rename(argument);
        }
      case 'new':
        final succeeded = await controller.newThread();
        if (succeeded && argument != null && argument.isNotEmpty) {
          await controller.rename(argument);
        }
      case 'clear':
        final succeeded = await controller.clearThread();
        if (succeeded && argument != null && argument.isNotEmpty) {
          await controller.rename(argument);
        }
      case 'resume':
        await _resumeThread(context, controller, state);
      case 'review':
        await _showMobileReviewDialog(context, controller);
      case 'compact':
        await controller.compact();
    }
    return true;
  }

  bool _isUnsupportedMobileSessionCommand(
    MobileCodexController controller,
    String draftText, {
    required bool hasAttachments,
  }) {
    if (hasAttachments) return false;
    final match = RegExp(
      r'^/(goal|new|clear|resume)(?:\s+.*)?$',
      caseSensitive: false,
    ).firstMatch(draftText.trim());
    if (match == null) return false;
    return switch (match.group(1)!.toLowerCase()) {
      'goal' => !controller.supportsGoals,
      _ => !controller.supportsSessions,
    };
  }

  bool _isMobileThreadSwitchCommand(
    String draftText, {
    required bool hasAttachments,
  }) =>
      !hasAttachments &&
      RegExp(
        r'^/(new|clear|resume)(?:\s+.*)?$',
        caseSensitive: false,
      ).hasMatch(draftText.trim());

  Future<void> _steer(MobileCodexController controller) async {
    final submissionRevision = _submissionRevision;
    final submissionHostId = widget.hostId;
    final submissionTabId = widget.tabId;
    final submissionThreadGeneration = controller.threadGeneration;
    final state = ref
        .read(mobileCodexControllerProvider(widget.hostId, widget.tabId))
        .value;
    final targetTurnId = state?.activeTurnId;
    final draftText = _composer.text;
    final attachments = List<Map<String, Object?>>.of(_attachments);
    final catalogSelections = _activeCatalogSelections();
    if (draftText.trim().isEmpty &&
        attachments.isEmpty &&
        catalogSelections.isEmpty) {
      return;
    }
    final submittedDraft = MobileCodexComposerDraft(
      value: _composer.value,
      attachments: attachments,
      catalogSelections: catalogSelections,
    );
    _setDraftState(() {
      _composer.clear();
      _attachments.clear();
      _catalogSelections.clear();
    });
    await _serializeMobileSubmission(
      submissionHostId,
      submissionTabId,
      () async {
        final resolvedPrompt = await _expandMobileSavedPrompt(
          controller,
          draftText,
          cwd: state?.activeCwd,
        );
        if (!_isCurrentMobileSubmission(
          submissionRevision,
          submissionHostId,
          submissionTabId,
          controller,
          submissionThreadGeneration,
        )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          return;
        }
        if (!resolvedPrompt.expanded &&
            state != null &&
            _isMobileGoalCommand(
              draftText,
              hasAttachments: attachments.isNotEmpty,
            ) &&
            await _runTypedMobileSessionCommand(
              controller,
              state,
              draftText,
              hasAttachments: attachments.isNotEmpty,
            )) {
          if (mounted) _composerFocus.requestFocus();
          return;
        }
        if (resolvedPrompt.failed ||
            !resolvedPrompt.expanded &&
                _isMobileTypedSessionCommand(
                  draftText,
                  hasAttachments: attachments.isNotEmpty,
                )) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          if (mounted) _composerFocus.requestFocus();
          return;
        }
        final activeTurnId = ref
            .read(mobileCodexControllerProvider(widget.hostId, widget.tabId))
            .value
            ?.activeTurnId;
        final accepted =
            activeTurnId == targetTurnId &&
            activeTurnId != null &&
            await controller.steer(
              resolvedPrompt.text,
              attachments: attachments,
              catalogSelections: catalogSelections,
            );
        if (!accepted) {
          _restoreAbandonedMobileSubmission(
            submissionHostId,
            submissionTabId,
            submittedDraft,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Steer was not accepted. Your message has been restored.',
                ),
              ),
            );
          }
        }
      },
    );
  }

  bool _isMobileTypedSessionCommand(
    String draftText, {
    required bool hasAttachments,
  }) =>
      !hasAttachments &&
      RegExp(
        r'^/(goal|rename|new|clear|resume|review|compact)(?:\s+.*)?$',
        caseSensitive: false,
      ).hasMatch(draftText.trim());

  bool _isMobileGoalCommand(String draftText, {required bool hasAttachments}) =>
      !hasAttachments &&
      RegExp(
        r'^/goal(?:\s+.*)?$',
        caseSensitive: false,
      ).hasMatch(draftText.trim());
}
