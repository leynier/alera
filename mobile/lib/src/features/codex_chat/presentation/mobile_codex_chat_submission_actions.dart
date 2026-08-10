part of 'mobile_codex_chat_screen.dart';

// This part keeps draft submission state separate from screen layout.
// ignore_for_file: invalid_use_of_protected_member

extension _MobileCodexSubmissionActions on _MobileCodexChatScreenState {
  Future<void> _serializeMobileSubmission(
    String hostId,
    String tabId,
    Future<void> Function() submission,
  ) {
    final previous = _submissionTail;
    final key = _mobileSubmissionKey(hostId, tabId);
    _pendingSubmissionCounts[key] = (_pendingSubmissionCounts[key] ?? 0) + 1;
    final next = () async {
      try {
        try {
          await previous;
        } on Object catch (error, stackTrace) {
          _MobileCodexChatScreenState._logger.warning(
            'An earlier Codex submission failed.',
            error,
            stackTrace,
          );
        }
        await submission();
      } finally {
        final remaining = (_pendingSubmissionCounts[key] ?? 1) - 1;
        if (remaining <= 0) {
          _pendingSubmissionCounts.remove(key);
        } else {
          _pendingSubmissionCounts[key] = remaining;
        }
      }
    }();
    _submissionTail = next;
    return next;
  }

  bool _hasPendingMobileSubmission(String hostId, String tabId) =>
      (_pendingSubmissionCounts[_mobileSubmissionKey(hostId, tabId)] ?? 0) > 0;

  String _mobileSubmissionKey(String hostId, String tabId) =>
      '$hostId\u{0}$tabId';

  bool _isCurrentMobileSubmission(
    int revision,
    String hostId,
    String tabId,
    MobileCodexController controller,
    int threadGeneration,
  ) =>
      mounted &&
      revision == _submissionRevision &&
      widget.hostId == hostId &&
      widget.tabId == tabId &&
      controller.threadGeneration == threadGeneration;

  void _restoreAbandonedMobileSubmission(
    String hostId,
    String tabId,
    MobileCodexComposerDraft submittedDraft,
  ) {
    _draftStore.restoreSubmission(hostId, tabId, submittedDraft);
  }

  Future<({String text, bool expanded, bool failed})> _expandMobileSavedPrompt(
    MobileCodexController controller,
    String input, {
    String? cwd,
  }) async {
    final match = RegExp(
      r'^/([^\s]+)(?:\s+(.*))?$',
      dotAll: true,
    ).firstMatch(input.trim());
    if (match == null) return (text: input, expanded: false, failed: false);
    if (!controller.supportsWorkspaceFiles) {
      return (text: input, expanded: false, failed: false);
    }
    try {
      final prompts = await controller.listSavedPrompts(
        widget.workspaceId,
        cwd: cwd,
      );
      final name = match.group(1)!.toLowerCase();
      for (final prompt in prompts) {
        if (prompt.name.toLowerCase() == name) {
          return (
            text: expandMobileCodexSavedPrompt(
              prompt.body,
              match.group(2)?.trim() ?? '',
            ),
            expanded: true,
            failed: false,
          );
        }
      }
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Could not expand a saved Codex prompt.',
        error,
        stackTrace,
      );
      return (text: input, expanded: false, failed: true);
    }
    return (text: input, expanded: false, failed: false);
  }
}
