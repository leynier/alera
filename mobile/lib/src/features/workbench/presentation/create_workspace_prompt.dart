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
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        TextField(
          controller: _prompt,
          enabled: !promptState.loading && created == null && !_uploadingImages,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Initial Prompt',
            hintText: 'Describe what the agent should build',
            alignLabelWithHint: true,
          ),
        ),
        if (widget.supportsPromptImageUpload) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          OutlinedButton.icon(
            onPressed:
                promptState.loading || created != null || _uploadingImages
                ? null
                : _addPromptImages,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Add Images'),
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
        if (_promptImageError != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            _promptImageError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _createAnother,
          onChanged: promptState.loading || created != null || _uploadingImages
              ? null
              : (value) {
                  _update(() => _createAnother = value ?? false);
                },
          title: const Text('Create Another'),
          subtitle: const Text('Keep this screen open after creation'),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        if (_uploadingImages)
          Row(
            children: <Widget>[
              const SizedBox.square(
                dimension: AleraTokens.spaceLg,
                child: CircularProgressIndicator(
                  strokeWidth: AleraTokens.strokeSm,
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              const Expanded(child: Text('Uploading images')),
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
                    _uploadingImages
                ? null
                : () => _createFromPrompt(controller),
            icon: const Icon(Icons.smart_toy_outlined),
            label: const Text('Create And Start Agent'),
          ),
      ],
    );
  }

  Future<void> _addPromptImages() async {
    _update(() {
      _uploadingImages = true;
    });
    try {
      final picker = widget.promptImagePicker ?? ImagePickerPromptImagePicker();
      final images = await picker.pickImages();
      if (images.isEmpty) {
        return;
      }
      final client = await ref.read(
        workspaceClientProvider(widget.hostId).future,
      );
      if (!client.supportsPromptImageUpload) {
        throw UnsupportedError(
          'Update Alera on this host to add images to a prompt.',
        );
      }
      for (final image in images) {
        final result = await client.uploadPromptImage(
          format: promptImageFormatForFileName(image.name),
          sizeBytes: image.sizeBytes,
          openRead: image.openRead,
        );
        if (!mounted) {
          return;
        }
        insertPromptImagePaths(_prompt, <String>[result.hostPath]);
      }
      if (mounted) {
        _update(() {
          _promptImageError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        _update(() {
          _promptImageError = _promptImageErrorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        _update(() {
          _uploadingImages = false;
        });
      }
    }
  }

  String _promptImageErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Could not add images. Try again.';
    }
    return 'Could not add images: $message';
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
        _promptImageError = null;
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
        _promptImageError = null;
        controller.resetForAnother();
      } else {
        _openWorkspace(creation, tabId: tabId);
      }
    }
  }
}
