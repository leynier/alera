part of 'create_workspace_screen.dart';

extension _CreateWorkspacePromptForm on _CreateWorkspaceScreenState {
  Widget _buildPromptForm(BuildContext context) {
    final promptState = ref.watch(
      promptWorkspaceControllerProvider(widget.hostId),
    );
    final controller = ref.read(
      promptWorkspaceControllerProvider(widget.hostId).notifier,
    );
    final created = promptState.creation;
    final workspaceFilesSourceId = _workspaceFilesSourceId(
      promptState.projectId,
    );
    final hasAttachmentSources =
        widget.supportsPromptImageUpload ||
        widget.supportsPromptFileUpload ||
        workspaceFilesSourceId != null;
    const promptDictationTarget = 'prompt-workspace';
    final promptEnabled =
        !promptState.loading && created == null && !_uploadingAttachment;
    final dictationEnabled =
        ref.watch(mobileAiDictationSettingsControllerProvider).value?.enabled ==
        true;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        if (dictationEnabled)
          MobileAiDictationReviewBar(
            hostId: widget.hostId,
            targetKey: promptDictationTarget,
          ),
        Stack(
          children: <Widget>[
            TextField(
              controller: _prompt,
              enabled: promptEnabled,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Initial Prompt',
                hintText: 'Describe what the agent should build',
                alignLabelWithHint: true,
                contentPadding: dictationEnabled
                    ? const EdgeInsets.fromLTRB(
                        AleraTokens.spaceMd,
                        AleraTokens.spaceMd,
                        AleraTokens.minTapTarget,
                        AleraTokens.minTapTarget,
                      )
                    : null,
              ),
            ),
            if (dictationEnabled)
              Positioned(
                right: AleraTokens.space4,
                bottom: AleraTokens.space4,
                child: MobileAiDictationControl(
                  key: const ValueKey<String>(
                    'prompt-workspace-dictation-control',
                  ),
                  hostId: widget.hostId,
                  targetKey: promptDictationTarget,
                  controller: _prompt,
                  enabled: promptEnabled,
                ),
              ),
          ],
        ),
        if (hasAttachmentSources) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          OutlinedButton.icon(
            onPressed:
                promptState.loading || created != null || _uploadingAttachment
                ? null
                : () => unawaited(
                    _showPromptAttachmentPicker(workspaceFilesSourceId),
                  ),
            icon: const Icon(Icons.attach_file),
            label: const Text('Add Attachment'),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceLg),
        AleraDropdownField<String>(
          value: promptState.projectId,
          labelText: 'Project',
          hintText: 'Select Project',
          entries: <AleraDropdownFieldEntry<String>>[
            for (final project in _orderedProjects)
              AleraDropdownFieldEntry<String>(
                value: project.id,
                label: project.name,
              ),
          ],
          enabled: !promptState.loading && created == null,
          filterable: true,
          filterHintText: 'Search Projects',
          onChanged: (value) => _selectPromptProject(value, controller),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        AleraDropdownField<String>(
          key: ValueKey<String?>(
            'prompt-source-${promptState.projectId}-${promptState.sourceBranch}',
          ),
          value: promptState.sourceBranch,
          labelText: 'Source Branch',
          hintText: promptState.loading ? 'Loading branches' : 'Select Branch',
          entries: <AleraDropdownFieldEntry<String>>[
            for (final branch in promptState.branches)
              AleraDropdownFieldEntry<String>(value: branch, label: branch),
          ],
          enabled: !promptState.loading && created == null,
          filterable: true,
          filterHintText: 'Search Branches',
          onChanged: controller.selectSourceBranch,
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        AleraDropdownField<String?>(
          key: ValueKey<String?>(
            'prompt-parent-${promptState.projectId}-$_promptParentWorkspaceId',
          ),
          value: _promptParentWorkspaceId,
          labelText: 'Parent Workspace',
          hintText: 'Select Parent Workspace',
          entries: <AleraDropdownFieldEntry<String?>>[
            const AleraDropdownFieldEntry<String?>(
              value: null,
              label: 'No Parent',
            ),
            for (final workspace in _parentWorkspacesFor(promptState.projectId))
              AleraDropdownFieldEntry<String?>(
                value: workspace.id,
                label: _parentWorkspaceLabel(workspace),
              ),
          ],
          enabled: !promptState.loading && created == null,
          filterable: true,
          filterHintText: 'Search Workspaces',
          onChanged: (value) {
            _update(() => _promptParentWorkspaceId = value);
          },
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        AleraDropdownField<String>(
          key: ValueKey<String?>('prompt-profile-${promptState.profileId}'),
          value: promptState.profileId,
          labelText: 'Agent Profile',
          hintText: promptState.profiles.isEmpty
              ? 'Create an agent profile in desktop settings'
              : 'Select Agent Profile',
          entries: <AleraDropdownFieldEntry<String>>[
            for (final profile in promptState.profiles)
              AleraDropdownFieldEntry<String>(
                value: profile.id,
                label: profile.name,
              ),
          ],
          enabled: !promptState.loading && created == null,
          filterable: true,
          filterHintText: 'Search Agent Profiles',
          onChanged: controller.selectProfile,
        ),
        if (promptState.error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            promptState.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_promptAttachmentError != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            _promptAttachmentError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: .leading,
          value: _createAnother,
          onChanged:
              promptState.loading || created != null || _uploadingAttachment
              ? null
              : (value) {
                  _update(() => _createAnother = value ?? false);
                },
          title: const Text('Create Another'),
          subtitle: const Text('Keep this screen open after creation'),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        if (_uploadingAttachment)
          Row(
            children: <Widget>[
              const SizedBox.square(
                dimension: AleraTokens.spaceLg,
                child: CircularProgressIndicator(
                  strokeWidth: AleraTokens.strokeSm,
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              const Expanded(child: Text('Uploading attachment')),
            ],
          )
        else if (promptState.loading)
          Row(
            children: <Widget>[
              const SizedBox.square(
                dimension: AleraTokens.spaceLg,
                child: CircularProgressIndicator(
                  strokeWidth: AleraTokens.strokeSm,
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              Expanded(child: Text(promptState.phase ?? 'Working')),
              if (promptState.phase == 'Generating workspace identity')
                TextButton(
                  onPressed: controller.cancelGeneration,
                  child: const Text('Cancel'),
                ),
            ],
          )
        else if (created != null)
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openWorkspace(created),
                  child: const Text('Open Workspace'),
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              Expanded(
                child: FilledButton(
                  onPressed: () => _retryPromptAgent(controller),
                  child: const Text('Retry Agent'),
                ),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed:
                promptState.projectId == null ||
                    promptState.sourceBranch == null ||
                    promptState.profileId == null ||
                    _uploadingAttachment
                ? null
                : () => _createFromPrompt(controller),
            icon: const Icon(Icons.smart_toy_outlined),
            label: const Text('Create And Start Agent'),
          ),
      ],
    );
  }

  Future<void> _createFromPrompt(PromptWorkspaceController controller) async {
    final selectedProjectId = ref
        .read(promptWorkspaceControllerProvider(widget.hostId))
        .projectId;
    final workspaceBranches = <String>{
      for (final workspace in widget.workspaces)
        if (workspace.status == 'active' &&
            workspace.projectId == selectedProjectId &&
            workspace.branch != null &&
            workspace.branch!.trim().isNotEmpty)
          workspace.branch!.trim(),
    };
    await controller.create(
      prompt: _prompt.text,
      workspaceBranches: workspaceBranches,
      parentWorkspaceId: _promptParentWorkspaceId,
    );
    if (!mounted) {
      return;
    }
    final state = ref.read(promptWorkspaceControllerProvider(widget.hostId));
    final creation = state.creation;
    final tabId = state.agentTabId;
    if (creation != null && tabId != null) {
      if (_createAnother) {
        _showCreationMessage(creation);
        _prompt.clear();
        _promptAttachmentError = null;
        controller.resetForAnother();
      } else {
        _openWorkspace(creation, tabId: tabId);
      }
    }
  }

  Future<void> _retryPromptAgent(PromptWorkspaceController controller) async {
    await controller.retryAgent(_prompt.text);
    if (!mounted) {
      return;
    }
    final state = ref.read(promptWorkspaceControllerProvider(widget.hostId));
    final creation = state.creation;
    final tabId = state.agentTabId;
    if (creation != null && tabId != null) {
      if (_createAnother) {
        _showCreationMessage(creation);
        _prompt.clear();
        _promptAttachmentError = null;
        controller.resetForAnother();
      } else {
        _openWorkspace(creation, tabId: tabId);
      }
    }
  }
}
