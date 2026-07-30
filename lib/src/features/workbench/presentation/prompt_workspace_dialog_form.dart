part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogForm on _PromptWorkspaceDialogState {
  Widget _buildPromptMode(ThemeData theme) {
    final created = _created;
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AleraTextField(
              controller: _promptController,
              labelText: 'Initial Prompt',
              hintText: 'Describe What The Agent Should Build',
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              enabled: !_working && created == null,
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraDropdownField<Project>(
              labelText: 'Project',
              value: _project,
              entries: <AleraDropdownFieldEntry<Project>>[
                for (final project in widget.projects)
                  AleraDropdownFieldEntry<Project>(
                    value: project,
                    label: project.name,
                  ),
              ],
              enabled: !_working && created == null,
              filterable: true,
              onChanged: _selectProject,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<String>(
              labelText: 'Source Branch',
              hintText: _loadingBranches ? 'Loading Branches' : 'Select Branch',
              value: _sourceBranch,
              entries: <AleraDropdownFieldEntry<String>>[
                for (final branch in _branches)
                  AleraDropdownFieldEntry<String>(value: branch, label: branch),
              ],
              enabled: !_working && !_loadingBranches && created == null,
              filterable: true,
              onChanged: (branch) => _update(() => _sourceBranch = branch),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<String?>(
              labelText: 'Parent Workspace',
              value: _selectedParentWorkspaceId,
              entries: <AleraDropdownFieldEntry<String?>>[
                const AleraDropdownFieldEntry<String?>(
                  value: null,
                  label: 'No Parent',
                ),
                for (final workspace in _parentWorkspaces)
                  AleraDropdownFieldEntry<String?>(
                    value: workspace.id,
                    label: _parentWorkspaceLabel(workspace),
                  ),
              ],
              enabled: !_working && created == null,
              filterable: true,
              filterHintText: 'Search Workspaces',
              onChanged: (workspaceId) =>
                  _update(() => _selectedParentWorkspaceId = workspaceId),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<AgentProfile>(
              labelText: 'Agent Profile',
              hintText: widget.agentProfiles.isEmpty
                  ? 'Create An Agent Profile In Settings'
                  : 'Select Agent Profile',
              value: _profile,
              entries: <AleraDropdownFieldEntry<AgentProfile>>[
                for (final profile in widget.agentProfiles)
                  AleraDropdownFieldEntry<AgentProfile>(
                    value: profile,
                    label: profile.name,
                  ),
              ],
              enabled: !_working && created == null,
              filterable: true,
              onChanged: (profile) => _update(() => _profile = profile),
            ),
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (_working) ...<Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(child: Text(_phase ?? 'Working')),
                  if (_activeOperationId != null)
                    TextButton(
                      onPressed: _cancelGeneration,
                      child: const Text('Cancel'),
                    ),
                ] else if (created != null) ...<Widget>[
                  OutlinedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(PromptWorkspaceDialogResult(creation: created)),
                    child: const Text('Open Workspace'),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    onPressed: _retryAgent,
                    child: const Text('Retry Agent'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed:
                        widget.projects.isEmpty ||
                            widget.agentProfiles.isEmpty ||
                            _loadingBranches
                        ? null
                        : _submit,
                    icon: const Icon(AleraIcons.agent, size: 16),
                    label: const Text('Create And Start Agent'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
