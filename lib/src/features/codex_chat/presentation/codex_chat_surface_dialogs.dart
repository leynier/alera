part of 'codex_chat_surface.dart';

extension _CodexSurfaceDialogs on _CodexChatSurfaceState {
  Future<void> _showStatus(BuildContext context, CodexChatState state) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Codex Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Workspace: ${state.activeCwd ?? widget.workspace.path}'),
              Text('Thread: ${widget.tab.title}'),
              Text('Model: ${state.selectedModel ?? 'Default'}'),
              Text('Reasoning: ${_choiceLabel(state.reasoningEffort)}'),
              Text('Plan Mode: ${state.planMode ? 'On' : 'Off'}'),
              Text(
                'Permissions: ${switch (state.permissionMode) {
                  'never' => 'Full Access',
                  'auto-review' => 'Approve For Me',
                  _ => 'Ask First',
                }}',
              ),
              Text('Queued Messages: ${state.queuedMessages.length}'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Future<void> _startReview(
    BuildContext context,
    CodexChatController controller,
    CodexChatState state,
  ) async {
    final workspacePath = state.activeCwd ?? widget.workspace.path;
    final git = ref.read(gitBackendProvider);
    var branches = const <String>[];
    var branchLookupFailed = false;
    try {
      branches = await git.listBranches(workspacePath);
    } catch (_) {
      branchLookupFailed = true;
    }
    try {
      final currentBranch = await git.currentBranch(workspacePath);
      if (currentBranch != 'HEAD') {
        branches = branches
            .where((branch) => branch != currentBranch)
            .toList(growable: false);
      }
    } catch (_) {
      // Branch selection remains useful when HEAD cannot be resolved.
    }
    if (!context.mounted) return;
    final selection = await showDialog<_CodexReviewSelection>(
      context: context,
      builder: (context) => _CodexReviewDialog(
        branches: branches,
        branchLookupFailed: branchLookupFailed,
      ),
    );
    if (selection == null || !mounted) return;
    await controller.startReview(
      target: selection.target.wireValue,
      argument: selection.argument,
      commitTitle: selection.commitTitle,
      delivery: selection.delivery.wireValue,
    );
  }
}
