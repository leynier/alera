part of 'mobile_codex_chat_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _MobileResumeActions on _MobileCodexChatScreenState {
  Future<void> _resumeThread(
    BuildContext context,
    MobileCodexController controller,
    MobileCodexState state,
  ) async {
    final selection = await showModalBottomSheet<_MobileResumeSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MobileCodexResumePicker(
        workspaceId: widget.workspaceId,
        loadPage: controller.loadThreads,
      ),
    );
    if (selection == null || !mounted || !context.mounted) return;
    final currentCwd = state.activeCwd;
    final selectedCwd = selection.thread.isBound
        ? _MobileResumeCwdChoice(currentCwd ?? selection.thread.cwd)
        : await _chooseMobileResumeCwd(
            context,
            thread: selection.thread,
            currentCwd: currentCwd,
          );
    if (selectedCwd == null || !mounted || !context.mounted) return;
    late final Map<String, Object?> response;
    try {
      response = await controller.resumeThread(
        selection.thread,
        cwd: selectedCwd.cwd,
      );
    } catch (_) {
      return;
    }
    if (!mounted || !context.mounted) return;
    if (response['alreadyBound'] == true) {
      final boundWorkspaceId = response['boundWorkspaceId']?.toString();
      final boundTabId = response['boundTabId']?.toString();
      if (boundWorkspaceId != null &&
          boundTabId != null &&
          boundWorkspaceId.isNotEmpty &&
          boundTabId.isNotEmpty) {
        widget.onFocusBoundTab?.call(boundWorkspaceId, boundTabId);
      }
    }
  }

  Future<_MobileResumeCwdChoice?> _chooseMobileResumeCwd(
    BuildContext context, {
    required MobileCodexThreadSummary thread,
    required String? currentCwd,
  }) async {
    final savedCwd = thread.cwd?.trim();
    final current = currentCwd?.trim();
    if (savedCwd == null || savedCwd.isEmpty) {
      return _MobileResumeCwdChoice(current);
    }
    final savedAvailable = thread.workspaceId?.isNotEmpty == true;
    if (current == null || current.isEmpty) {
      return _MobileResumeCwdChoice(savedAvailable ? savedCwd : null);
    }
    if (savedCwd == current) return _MobileResumeCwdChoice(current);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Working Folder'),
        content: Text(
          savedAvailable
              ? 'Resume in the current Codex folder or switch only this chat to its saved folder.\n\nCurrent: $current\nSaved: $savedCwd'
              : 'The saved folder is outside the workspaces available to Alera. This chat can still resume in the current Codex folder.\n\nCurrent: $current\nSaved: $savedCwd',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(current),
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
    return selected == null ? null : _MobileResumeCwdChoice(selected);
  }
}

class const _MobileResumeCwdChoice(final String? cwd);
