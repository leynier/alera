part of 'create_workspace_screen.dart';

extension _CreateWorkspaceManualForm on _CreateWorkspaceScreenState {
  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _projectId,
          decoration: const InputDecoration(labelText: 'Project'),
          items: <DropdownMenuItem<String>>[
            for (final project in widget.projects)
              DropdownMenuItem<String>(
                value: project.id,
                child: Text(project.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _creating
              ? null
              : (value) {
                  if (value != null) {
                    _selectProject(value);
                  }
                },
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        TextField(
          controller: _branch,
          enabled: !_creating,
          onChanged: (_) => _update(() {}),
          decoration: const InputDecoration(
            labelText: 'Branch Name',
            helperText: 'The Worktree Branch For This Workspace',
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
            DropdownButtonFormField<String>(
              initialValue: _sourceBranch,
              decoration: const InputDecoration(labelText: 'Source Branch'),
              items: <DropdownMenuItem<String>>[
                for (final branch in _branches)
                  DropdownMenuItem<String>(
                    value: branch,
                    child: Text(branch, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _creating
                  ? null
                  : (value) {
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
        DropdownButtonFormField<String?>(
          initialValue: _parentWorkspaceId,
          decoration: const InputDecoration(labelText: 'Parent Workspace'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No Parent'),
            ),
            for (final workspace in widget.workspaces)
              if (workspace.projectId == _projectId)
                DropdownMenuItem<String?>(
                  value: workspace.id,
                  child: Text(workspace.name, overflow: TextOverflow.ellipsis),
                ),
          ],
          onChanged: _creating
              ? null
              : (value) {
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
          controlAffinity: ListTileControlAffinity.leading,
          value: _createAnother,
          onChanged: _creating
              ? null
              : (value) {
                  _update(() {
                    _createAnother = value ?? false;
                  });
                },
          title: const Text('Create Another'),
          subtitle: const Text('Keep This Screen Open After Creation'),
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
