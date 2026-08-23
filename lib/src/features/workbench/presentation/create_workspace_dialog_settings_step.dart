part of 'create_workspace_dialog.dart';

class _CreateWorkspaceSettingsStep extends StatelessWidget {
  const _CreateWorkspaceSettingsStep({
    required this.project,
    required this.sourceBranch,
    required this.reuseExistingBranch,
    required this.newBranchController,
    required this.newBranchError,
    required this.branchValidationError,
    required this.isValidatingBranch,
    required this.onNewBranchChanged,
    required this.nameController,
    required this.nameTouched,
    required this.onNameChanged,
    required this.parentCandidates,
    required this.selectedParentWorkspaceId,
    required this.onParentWorkspaceChanged,
    required this.creating,
    required this.onSubmit,
  });

  final Project? project;
  final String sourceBranch;
  final bool reuseExistingBranch;
  final TextEditingController newBranchController;
  final String? newBranchError;
  final String? branchValidationError;
  final bool isValidatingBranch;
  final ValueChanged<String> onNewBranchChanged;
  final TextEditingController nameController;
  final bool nameTouched;
  final ValueChanged<String> onNameChanged;
  final List<WorkspaceParentCandidate> parentCandidates;
  final String? selectedParentWorkspaceId;
  final ValueChanged<String?> onParentWorkspaceChanged;
  final bool creating;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
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

class _WorkspaceSelectionSummary extends StatelessWidget {
  const _WorkspaceSelectionSummary({
    required this.projectName,
    required this.sourceBranch,
    required this.reuseExistingBranch,
  });

  final String projectName;
  final String sourceBranch;
  final bool reuseExistingBranch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
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
                  fontWeight: FontWeight.w500,
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
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkspaceNameField extends StatelessWidget {
  const _WorkspaceNameField({
    required this.controller,
    required this.enabled,
    required this.showSync,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool showSync;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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

class _WorkspaceNameSyncBadge extends StatelessWidget {
  const _WorkspaceNameSyncBadge();

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
        mainAxisSize: MainAxisSize.min,
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCreationPreview extends StatelessWidget {
  const _WorkspaceCreationPreview({
    required this.project,
    required this.sourceBranch,
    required this.newBranchName,
    required this.workspaceName,
    required this.reuseExistingBranch,
    required this.parentLabel,
  });

  final Project? project;
  final String sourceBranch;
  final String newBranchName;
  final String workspaceName;
  final bool reuseExistingBranch;
  final String? parentLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.text,
    this.useMonoStyle = true,
  });

  final IconData icon;
  final String text;
  final bool useMonoStyle;

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
            overflow: TextOverflow.ellipsis,
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
