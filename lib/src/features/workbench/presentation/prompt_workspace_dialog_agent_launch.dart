part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogAgentLaunch on _PromptWorkspaceDialogState {
  Future<void> _retryAgent() async {
    final creation = _created;
    final profile = _profile;
    final prompt = _promptController.text.trim();
    if (creation == null || profile == null || prompt.isEmpty) {
      return;
    }
    _update(() {
      _working = true;
      _phase = 'Starting agent';
      _error = null;
    });
    try {
      final currentHostSupportsIdempotency = await widget
          .supportsIdempotentAgentLaunch();
      if (!mounted) {
        return;
      }
      if (_originalAgentLaunchWasIdempotent != true ||
          !currentHostSupportsIdempotency) {
        throw UnsupportedError(
          'Update Alera on this host before retrying agent launch safely.',
        );
      }
      final clientMutationId = _agentLaunchMutationId;
      if (clientMutationId == null) {
        throw StateError('The original agent launch identity is unavailable.');
      }
      final launch = await widget.launchAgent(
        workspaceId: creation.workspace.id,
        profileId: profile.id,
        prompt: prompt,
        clientMutationId: clientMutationId,
        requireIdempotency: true,
      );
      if (mounted) {
        await _finishCreation(creation, launch.tabId);
      }
    } catch (error) {
      if (mounted) {
        _update(() {
          _working = false;
          _phase = null;
          _error = error.toString();
        });
      }
    }
  }
}
