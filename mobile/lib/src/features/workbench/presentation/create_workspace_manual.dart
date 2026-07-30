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
            for (final project in _orderedProjects)
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
            for (final workspace in _orderedParentWorkspaces)
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

class _SetupReportView extends StatelessWidget {
  const _SetupReportView({required this.result, required this.onDone});

  final WorkspaceCreationResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline, color: AleraTokens.success),
            const SizedBox(width: AleraTokens.spaceSm),
            Expanded(
              child: Text(
                result.workspace.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        for (final step in result.steps)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              step.succeeded ? Icons.check : Icons.close,
              color: step.succeeded ? AleraTokens.success : AleraTokens.error,
            ),
            title: Text(step.label, overflow: TextOverflow.ellipsis),
            subtitle: step.message == null
                ? null
                : Text(step.message!, overflow: TextOverflow.ellipsis),
          ),
        const SizedBox(height: AleraTokens.spaceXl),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
