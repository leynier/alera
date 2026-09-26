part of 'agent_profile_launch_dialog.dart';

extension _AgentProfileLaunchDialogContent on _AgentProfileLaunchDialogState {
  Widget _buildDialog(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 620,
      maxHeight: 720,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(AleraIcons.agent, color: AleraTokens.accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Start ${widget.profile.name}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: .bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _working
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(AleraIcons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              _resume
                  ? 'Resume an existing ${agentDisplayName(agentProfileAdapterFromKey(widget.profile.agentType)!)} conversation in a new tab.'
                  : 'Write a starting prompt, attach files, or start without a prompt.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraSegmentedButton<bool>(
              segments: <ButtonSegment<bool>>[
                ButtonSegment(
                  value: false,
                  label: const Text('New Session'),
                  enabled: !_working,
                ),
                ButtonSegment(
                  value: true,
                  label: const Text('Resume Session'),
                  enabled: !_working && _supportsResume == true,
                ),
              ],
              selected: _resume,
              onSelectionChanged: (value) {
                _update(() {
                  _resume = value;
                  _error = null;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    (_resume ? _sessionFocusNode : _promptFocusNode)
                        .requestFocus();
                  }
                });
              },
            ),
            if (_supportsResume == false) ...[
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Session resume is unavailable for this runtime or agent.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AleraTokens.space16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    if (_resume) ...[
                      AleraTextField(
                        controller: _sessionController,
                        focusNode: _sessionFocusNode,
                        labelText: 'Session ID',
                        hintText: 'Paste a session ID',
                        enabled: !_working,
                        onChanged: (_) => _update(() => _error = null),
                        onCommandEnter: () => unawaited(_submit(skip: false)),
                      ),
                      const SizedBox(height: AleraTokens.space12),
                      Text(
                        'Uses this profile’s settings where supported.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_sessionController.text.isNotEmpty &&
                          !isUsableAgentSessionId(_sessionController.text))
                        Text(
                          'Enter a valid session ID without spaces or shell operators.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.error,
                          ),
                        ),
                    ] else ...[
                      AiDictationFieldOverlay(
                        controller: _promptController,
                        focusNode: _promptFocusNode,
                        initialPrompt:
                            'The user is describing a software task for Alera.',
                        controlKey: const ValueKey<String>(
                          'agent-profile-launch-dictation-control',
                        ),
                        enabled: !_working,
                        child: AleraTextField(
                          controller: _promptController,
                          focusNode: _promptFocusNode,
                          labelText: 'Initial Prompt',
                          hintText: 'Describe what the agent should do or paste an image',
                          minLines: 4,
                          maxLines: 8,
                          autofocus: true,
                          enabled: !_working,
                          onChanged: (_) {
                            if (_error != null || !_working) {
                              _update(() {});
                            }
                          },
                          onPaste: _pasteClipboard,
                          onCommandEnter: () => unawaited(_submit(skip: false)),
                          suffix: const SizedBox(width: AleraTokens.space32),
                        ),
                      ),
                      TerminalComposerAttachmentBar(
                        attachments: _attachments,
                        onRemove: (id) {
                          _update(
                            () => _attachments.removeWhere(
                              (attachment) => attachment.id == id,
                            ),
                          );
                        },
                        onOpenFile: (path) => unawaited(_openFile(path)),
                        enabled: !_working,
                      ),
                      const SizedBox(height: AleraTokens.space12),
                      OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () => unawaited(_addFiles()),
                        icon: const Icon(AleraIcons.attach, size: 16),
                        label: const Text('Add Files'),
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: AleraTokens.space16),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AleraTokens.space20),
                    Row(
                      children: <Widget>[
                        if (_working) ...<Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AleraTokens.space8),
                          Expanded(
                            child: Text(
                              _resume ? 'Resuming session…' : 'Starting agent',
                            ),
                          ),
                        ] else ...<Widget>[
                          const Spacer(),
                          TextButton(
                            onPressed: _resume
                                ? () => Navigator.of(context).pop()
                                : () => unawaited(_submit(skip: true)),
                            child: Text(
                              _resume ? 'Cancel' : 'Start Without Prompt',
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space8),
                          FilledButton.icon(
                            onPressed: _canStart
                                ? () => unawaited(_submit(skip: false))
                                : null,
                            icon: const Icon(AleraIcons.agent, size: 16),
                            label: Text(
                              _resume ? 'Resume Session' : 'Start Agent',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
