part of 'create_workspace_screen.dart';

extension _CreateWorkspaceManualForm on _CreateWorkspaceScreenState {
  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        AleraDropdownField<String>(
          value: _projectId,
          labelText: 'Project',
          hintText: 'Select Project',
          entries: <AleraDropdownFieldEntry<String>>[
            for (final project in _orderedProjects)
              AleraDropdownFieldEntry<String>(
                value: project.id,
                label: project.name,
              ),
          ],
          enabled: !_creating,
          filterable: true,
          filterHintText: 'Search Projects',
          onChanged: _selectProject,
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        TextField(
          controller: _branch,
          enabled: !_creating,
          onChanged: (_) => _update(() {}),
          decoration: const InputDecoration(
            labelText: 'Branch Name',
            helperText: 'The worktree branch for this workspace',
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _reuseExistingBranch,
          onChanged: _creating
              ? null
              : (value) {
                  _update(() {
                    _reuseExistingBranch = value;
                  });
                },
          title: const Text('Reuse Existing Branch'),
        ),
        if (!_reuseExistingBranch) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          if (_loadingBranches)
            const Center(child: CircularProgressIndicator())
          else
            AleraDropdownField<String>(
              value: _sourceBranch,
              labelText: 'Source Branch',
              hintText: _loadingBranches ? 'Loading branches' : 'Select Branch',
              entries: <AleraDropdownFieldEntry<String>>[
                for (final branch in _branches)
                  AleraDropdownFieldEntry<String>(value: branch, label: branch),
              ],
              enabled: !_creating && !_loadingBranches,
              filterable: true,
              filterHintText: 'Search Branches',
              onChanged: (value) {
                _update(() {
                  _sourceBranch = value;
                });
              },
            ),
        ],
        const SizedBox(height: AleraTokens.spaceLg),
        TextField(
          controller: _name,
          enabled: !_creating,
          decoration: const InputDecoration(
            labelText: 'Display Name (Optional)',
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        AleraDropdownField<String?>(
          value: _parentWorkspaceId,
          labelText: 'Parent Workspace',
          hintText: 'Select Parent Workspace',
          entries: <AleraDropdownFieldEntry<String?>>[
            const AleraDropdownFieldEntry<String?>(
              value: null,
              label: 'No Parent',
            ),
            for (final workspace in _orderedParentWorkspaces)
              AleraDropdownFieldEntry<String?>(
                value: workspace.id,
                label: _parentWorkspaceLabel(workspace),
              ),
          ],
          enabled: !_creating,
          filterable: true,
          filterHintText: 'Search Workspaces',
          onChanged: (value) {
            _update(() {
              _parentWorkspaceId = value;
            });
          },
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: .leading,
          value: _createAnother,
          onChanged: _creating
              ? null
              : (value) {
                  _update(() {
                    _createAnother = value ?? false;
                  });
                },
          title: const Text('Create Another'),
          subtitle: const Text('Keep this screen open after creation'),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        FilledButton.icon(
          onPressed: _canSubmit ? _create : null,
          icon: _creating
              ? const SizedBox.square(
                  dimension: AleraTokens.spaceLg,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                  ),
                )
              : const Icon(Icons.add),
          label: Text(_creating ? 'Creating' : 'Create Workspace'),
        ),
      ],
    );
  }
}
