part of 'create_workspace_dialog.dart';

class const _CreateWorkspaceSettingsStep({
  required final Project? project,
  required final String sourceBranch,
  required final bool reuseExistingBranch,
  required final TextEditingController newBranchController,
  required final String? newBranchError,
  required final String? branchValidationError,
  required final bool isValidatingBranch,
  required final ValueChanged<String> onNewBranchChanged,
  required final TextEditingController nameController,
  required final bool nameTouched,
  required final ValueChanged<String> onNameChanged,
  required final List<WorkspaceParentCandidate> parentCandidates,
  required final String? selectedParentWorkspaceId,
  required final ValueChanged<String?> onParentWorkspaceChanged,
  required final bool creating,
  required final VoidCallback onSubmit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: <Widget>[
        _WorkspaceSelectionSummary(
          projectName: project?.name ?? '',
          sourceBranch: sourceBranch,
          reuseExistingBranch: reuseExistingBranch,
        ),
        const SizedBox(height: AleraTokens.space16),
        if (reuseExistingBranch)
          AleraTextField(
            controller: newBranchController,
            enabled: false,
            labelText: 'Existing Branch *',
            errorText: newBranchError,
          )
        else
          AleraTextField(
            controller: newBranchController,
            autofocus: true,
            enabled: !creating,
            labelText: 'New Branch Name *',
            hintText: 'e.g. feature/terminal-tabs',
            errorText: newBranchError ?? branchValidationError,
            suffix: isValidatingBranch
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : null,
            onChanged: onNewBranchChanged,
            onSubmitted: (_) => onSubmit(),
          ),
        const SizedBox(height: AleraTokens.space12),
        _WorkspaceNameField(
          controller: nameController,
          enabled: !creating,
          showSync: !nameTouched && newBranchController.text.isNotEmpty,
          onChanged: onNameChanged,
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraDropdownField<String?>(
          value: selectedParentWorkspaceId,
          labelText: 'Parent Workspace',
          enabled: !creating,
          filterable: true,
          filterHintText: 'Search Workspaces',
          entries: <AleraDropdownFieldEntry<String?>>[
            const AleraDropdownFieldEntry<String?>(
              value: null,
              label: 'No Parent',
            ),
            for (final candidate in parentCandidates)
              AleraDropdownFieldEntry<String?>(
                value: candidate.workspace.id,
                label: _workspaceParentLabel(candidate),
              ),
          ],
          onChanged: onParentWorkspaceChanged,
        ),
        const SizedBox(height: AleraTokens.space16),
        _WorkspaceCreationPreview(
          project: project,
          sourceBranch: sourceBranch,
          newBranchName: newBranchController.text,
          workspaceName: nameController.text,
          reuseExistingBranch: reuseExistingBranch,
          parentLabel: _selectedWorkspaceParentLabel(
            parentCandidates,
            selectedParentWorkspaceId,
          ),
        ),
      ],
    );
  }
}

class const _WorkspaceSelectionSummary({
  required final String projectName,
  required final String sourceBranch,
  required final bool reuseExistingBranch,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: .infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        children: [
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  right: AleraTokens.space12,
                  bottom: AleraTokens.space4,
                ),
                child: Text(
                  'Project:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
              Text(
                projectName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w500,
                ),
              ),
            ],
          ),
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AleraTokens.space12),
                child: Text(
                  reuseExistingBranch ? 'Existing Branch:' : 'Source Branch:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
              Text(
                sourceBranch,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class const _WorkspaceNameField({
  required final TextEditingController controller,
  required final bool enabled,
  required final bool showSync,
  required final ValueChanged<String> onChanged,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .center,
      children: [
        Expanded(
          child: AleraTextField(
            controller: controller,
            enabled: enabled,
            labelText: 'Workspace Name (Optional)',
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        if (showSync) ...[
          const SizedBox(width: AleraTokens.space8),
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.space16),
            child: _WorkspaceNameSyncBadge(),
          ),
        ],
      ],
    );
  }
}

class const _WorkspaceNameSyncBadge() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: .min,
        children: [
          Icon(
            AleraIcons.link,
            size: 10,
            color: AleraTokens.accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: AleraTokens.space4),
          Text(
            'Sync',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.accent,
              fontWeight: .w500,
            ),
          ),
        ],
      ),
    );
  }
}

class const _WorkspaceCreationPreview({
  required final Project? project,
  required final String sourceBranch,
  required final String newBranchName,
  required final String workspaceName,
  required final bool reuseExistingBranch,
  required final String? parentLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          'Preview',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space6),
        Container(
          width: .infinity,
          padding: const EdgeInsets.all(AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              _PreviewRow(
                icon: AleraIcons.folder,
                text: _previewWorkspacePath(
                  project,
                  workspaceName,
                  newBranchName,
                ),
              ),
              const SizedBox(height: AleraTokens.space6),
              _PreviewRow(
                icon: AleraIcons.gitFork,
                text: _previewBranch(
                  sourceBranch,
                  newBranchName,
                  reuseExistingBranch,
                ),
              ),
              if (parentLabel case final label?) ...[
                const SizedBox(height: AleraTokens.space6),
                _PreviewRow(
                  icon: AleraIcons.link,
                  text: 'Parent: $label',
                  useMonoStyle: false,
                ),
              ],
              const SizedBox(height: AleraTokens.space6),
              const _PreviewRow(
                icon: AleraIcons.terminal,
                text: 'Initial terminal tab will be opened',
                useMonoStyle: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class const _PreviewRow({
  required final IconData icon,
  required final String text,
  final bool useMonoStyle = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: AleraTokens.foregroundMuted.withValues(alpha: 0.7),
        ),
        const SizedBox(width: AleraTokens.space6),
        Expanded(
          child: Text(
            text,
            overflow: .ellipsis,
            style: useMonoStyle
                ? AleraTokens.monoStyle.copyWith(
                    color: AleraTokens.foregroundMuted,
                  )
                : theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
          ),
        ),
      ],
    );
  }
}

String _workspaceParentLabel(WorkspaceParentCandidate candidate) {
  final branch = candidate.workspace.branch;
  final suffix = branch == null || branch.isEmpty ? '' : ' - $branch';
  return '${candidate.project.name} / ${candidate.workspace.name}$suffix';
}

String? _selectedWorkspaceParentLabel(
  List<WorkspaceParentCandidate> candidates,
  String? selectedId,
) {
  if (selectedId == null) {
    return null;
  }
  for (final candidate in candidates) {
    if (candidate.workspace.id == selectedId) {
      return _workspaceParentLabel(candidate);
    }
  }
  return null;
}

String _previewWorkspacePath(
  Project? project,
  String workspaceName,
  String newBranchName,
) {
  if (project == null) {
    return '';
  }
  final displayName = workspaceName.trim().isNotEmpty
      ? workspaceName.trim()
      : newBranchName.trim();
  final workspaceSlug = displayName.isNotEmpty
      ? _slugifyWorkspaceName(displayName)
      : 'workspace';
  return '~/.alera/workspaces/${_slugifyWorkspaceName(project.name)}-${project.id}/$workspaceSlug';
}

String _previewBranch(
  String sourceBranch,
  String newBranchName,
  bool reuseExistingBranch,
) {
  if (reuseExistingBranch) {
    final branch = sourceBranch.isEmpty ? '<existing-branch>' : sourceBranch;
    return 'Branch: $branch';
  }
  final target = newBranchName.isEmpty ? '<new-branch>' : newBranchName;
  final source = sourceBranch.isEmpty ? '<source>' : sourceBranch;
  return 'Branch: $target ← from $source';
}

String _slugifyWorkspaceName(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_/]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
