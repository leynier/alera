part of 'codex_chat_surface.dart';

// This extension keeps stateful session actions separate from the surface layout.
// ignore_for_file: invalid_use_of_protected_member

extension _CodexSurfaceSessionActions on _CodexChatSurfaceState {
  Future<void> _runComposerCommand(
    BuildContext context,
    CodexChatController controller,
    CodexChatState state,
    CodexComposerCommand command,
  ) async {
    switch (command) {
      case CodexComposerCommand.newChat:
        if (state.supportsSessions) {
          await controller.newThread();
        } else {
          await _openLegacyCodexTab();
        }
      case CodexComposerCommand.clear:
        if (state.supportsSessions) {
          await controller.clearThread();
        } else {
          await _openLegacyCodexTab();
        }
      case CodexComposerCommand.resume:
        if (state.supportsSessions) {
          await _resumeThread(context, controller, state);
        }
      case CodexComposerCommand.compact:
        await controller.compact();
      case CodexComposerCommand.review:
        await _startReview(context, controller, state);
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
                child: const Text('Ask For Approval'),
              ),
              if (state.supportsAutoReview)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop('auto-review'),
                  child: const Text('Approve For Me'),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('never'),
                child: const Text('Full Access'),
              ),
            ],
          ),
        );
        if (mode != null && context.mounted) {
          await _applyCodexPermissionSelection(
            context,
            mode,
            controller.setPermissionMode,
          );
        }
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

  Future<void> _openLegacyCodexTab() => ref
      .read(workbenchControllerProvider.notifier)
      .createCodexTab(widget.workspace);

  Future<void> _resumeThread(
    BuildContext context,
    CodexChatController controller,
    CodexChatState state,
  ) async {
    final selection = await showDialog<_CodexResumeSelection>(
      context: context,
      builder: (context) => _CodexResumePickerDialog(
        workspace: widget.workspace,
        loadPage: controller.loadThreads,
      ),
    );
    if (selection == null || !mounted || !context.mounted) return;
    final currentCwd = state.activeCwd ?? widget.workspace.path;
    final selectedCwd = selection.thread.isBound
        ? currentCwd
        : await _chooseResumeCwd(
            context,
            thread: selection.thread,
            currentCwd: currentCwd,
          );
    if (selectedCwd == null || !mounted || !context.mounted) return;
    late final Map<String, Object?> response;
    try {
      response = await controller.resumeThread(
        selection.thread,
        cwd: selectedCwd,
      );
    } catch (_) {
      return;
    }
    if (response['alreadyBound'] != true) return;
    final boundTabId = response['boundTabId']?.toString();
    final boundWorkspaceId = response['boundWorkspaceId']?.toString();
    if (boundTabId == null ||
        boundWorkspaceId == null ||
        boundTabId.isEmpty ||
        boundWorkspaceId.isEmpty) {
      return;
    }
    await ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspaceTab(workspaceId: boundWorkspaceId, tabId: boundTabId);
  }

  Future<String?> _chooseResumeCwd(
    BuildContext context, {
    required CodexThreadSummary thread,
    required String currentCwd,
  }) async {
    final savedCwd = thread.cwd?.trim();
    if (savedCwd == null || savedCwd.isEmpty || savedCwd == currentCwd) {
      return currentCwd;
    }
    final savedAvailable = thread.workspaceId?.isNotEmpty == true;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Working Folder'),
        content: Text(
          savedAvailable
              ? 'Resume in the current Codex folder or switch only this chat to its saved folder.\n\nCurrent: $currentCwd\nSaved: $savedCwd'
              : 'The saved folder is outside the workspaces available to Alera. This chat can still resume in the current Codex folder.\n\nCurrent: $currentCwd\nSaved: $savedCwd',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(currentCwd),
            child: const Text('Use Current Folder'),
          ),
          if (savedAvailable)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(savedCwd),
              child: const Text('Use Saved Folder'),
            ),
        ],
      ),
    );
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
}
