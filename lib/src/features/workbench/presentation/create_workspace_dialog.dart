import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

class CreateWorkspaceResult {
  const CreateWorkspaceResult({
    required this.project,
    required this.sourceBranch,
    required this.newBranchName,
    this.name,
  });

  final Project project;
  final String sourceBranch;
  final String newBranchName;
  final String? name;
}

class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({
    super.key,
    required this.projects,
    required this.loadBranches,
    this.initialProject,
  });

  final List<Project> projects;
  final Project? initialProject;
  final Future<List<String>> Function(Project project) loadBranches;

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  final TextEditingController _projectSearchController =
      TextEditingController();
  final TextEditingController _branchSearchController = TextEditingController();
  final TextEditingController _sourceBranchController = TextEditingController();
  final TextEditingController _newBranchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  Project? _selectedProject;
  List<String> _branches = const <String>[];
  String? _selectedSourceBranch;
  bool _nameTouched = false;
  bool _loadingBranches = false;
  String? _branchesError;
  String _projectQuery = '';
  String _branchQuery = '';
  String? _sourceBranchError;
  String? _newBranchError;

  @override
  void initState() {
    super.initState();
    _selectedProject = _pickInitialProject();
    final project = _selectedProject;
    if (project != null) {
      _loadBranches(project);
    }
  }

  @override
  void dispose() {
    _projectSearchController.dispose();
    _branchSearchController.dispose();
    _sourceBranchController.dispose();
    _newBranchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Project? _pickInitialProject() {
    final initial = widget.initialProject;
    if (initial != null) {
      for (final project in widget.projects) {
        if (project.id == initial.id) {
          return project;
        }
      }
    }
    if (widget.projects.isEmpty) {
      return null;
    }
    return widget.projects.first;
  }

  String? _pickDefaultSourceBranch(List<String> branches) {
    for (final preferred in const <String>[
      'main',
      'origin/main',
      'master',
      'origin/master',
    ]) {
      if (branches.contains(preferred)) {
        return preferred;
      }
    }
    if (branches.isEmpty) {
      return null;
    }
    return branches.first;
  }

  Future<void> _loadBranches(Project project) async {
    setState(() {
      _loadingBranches = true;
      _branchesError = null;
      _branches = const <String>[];
      _selectedSourceBranch = null;
      _sourceBranchController.clear();
      _branchSearchController.clear();
      _branchQuery = '';
    });
    try {
      final branches = await widget.loadBranches(project);
      if (!mounted || _selectedProject?.id != project.id) {
        return;
      }
      final defaultBranch = _pickDefaultSourceBranch(branches);
      setState(() {
        _branches = branches;
        _selectedSourceBranch = defaultBranch;
        if (defaultBranch != null) {
          _sourceBranchController.text = defaultBranch;
        }
        _loadingBranches = false;
      });
    } catch (error) {
      if (!mounted || _selectedProject?.id != project.id) {
        return;
      }
      setState(() {
        _branchesError = error.toString();
        _loadingBranches = false;
      });
    }
  }

  void _selectProject(Project project) {
    if (_selectedProject?.id == project.id) {
      return;
    }
    setState(() {
      _selectedProject = project;
      _sourceBranchError = null;
    });
    _loadBranches(project);
  }

  void _selectSourceBranch(String branch) {
    setState(() {
      _selectedSourceBranch = branch;
      _sourceBranchController.text = branch;
      _sourceBranchError = null;
    });
  }

  void _submit() {
    final project = _selectedProject;
    if (project == null) {
      return;
    }
    final sourceBranch = (_selectedSourceBranch ?? _sourceBranchController.text)
        .trim();
    final newBranchName = _newBranchController.text.trim();
    final name = _nameController.text.trim();
    final sourceBranchError = sourceBranch.isEmpty
        ? 'Source branch is required'
        : null;
    final newBranchError = newBranchName.isEmpty
        ? 'New branch name is required'
        : null;
    if (sourceBranchError != null || newBranchError != null) {
      setState(() {
        _sourceBranchError = sourceBranchError;
        _newBranchError = newBranchError;
      });
      return;
    }
    Navigator.of(context).pop(
      CreateWorkspaceResult(
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        name: name.isEmpty ? null : name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProject = _selectedProject;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.account_tree_outlined, color: AleraTokens.accent),
          const SizedBox(width: AleraTokens.space8),
          Text('New workspace', style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ProjectPicker(
                projects: widget.projects,
                selectedProject: selectedProject,
                query: _projectQuery,
                controller: _projectSearchController,
                onQueryChanged: (value) {
                  setState(() => _projectQuery = value);
                },
                onSelectProject: _selectProject,
              ),
              const SizedBox(height: AleraTokens.space16),
              if (_loadingBranches)
                const _LoadingBranches()
              else if (_branches.isNotEmpty)
                _SourceBranchPicker(
                  branches: _branches,
                  selectedBranch: _selectedSourceBranch,
                  query: _branchQuery,
                  controller: _branchSearchController,
                  errorText: _sourceBranchError,
                  onQueryChanged: (value) {
                    setState(() => _branchQuery = value);
                  },
                  onSelectBranch: _selectSourceBranch,
                )
              else ...<Widget>[
                if (_branchesError != null) ...<Widget>[
                  Text(
                    _branchesError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.error,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space8),
                ],
                TextField(
                  controller: _sourceBranchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Source branch',
                    hintText: 'e.g. main',
                    errorText: _sourceBranchError,
                  ),
                  onChanged: (_) {
                    setState(() => _sourceBranchError = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: AleraTokens.space12),
              TextField(
                controller: _newBranchController,
                autofocus: _branches.isNotEmpty,
                decoration: InputDecoration(
                  labelText: 'New branch name',
                  hintText: 'e.g. feature/terminal-tabs',
                  errorText: _newBranchError,
                ),
                onChanged: (value) {
                  if (!_nameTouched) {
                    _nameController.text = value.trim();
                  }
                  setState(() => _newBranchError = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AleraTokens.space12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Workspace name (optional)',
                ),
                onChanged: (_) => _nameTouched = true,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AleraTokens.space12),
              Container(
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  border: Border.all(color: AleraTokens.borderSubtle),
                ),
                child: Text(
                  'Alera will create a new git worktree from the selected source branch and open it as a workspace with its own terminal tabs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selectedProject == null || _loadingBranches
              ? null
              : _submit,
          child: const Text('Create workspace'),
        ),
      ],
    );
  }
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.selectedProject,
    required this.query,
    required this.controller,
    required this.onQueryChanged,
    required this.onSelectProject,
  });

  final List<Project> projects;
  final Project? selectedProject;
  final String query;
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Project> onSelectProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = <Project>[
      for (final project in projects)
        if (normalizedQuery.isEmpty ||
            project.name.toLowerCase().contains(normalizedQuery) ||
            project.repoPath.toLowerCase().contains(normalizedQuery))
          project,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Project',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        _SearchField(
          controller: controller,
          hintText: 'Search projects',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          child: filtered.isEmpty
              ? _EmptyPickerMessage(message: 'No projects match "$query"')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final project = filtered[index];
                    final selected = project.id == selectedProject?.id;
                    return _ProjectOption(
                      project: project,
                      selected: selected,
                      onTap: () => onSelectProject(project),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SourceBranchPicker extends StatelessWidget {
  const _SourceBranchPicker({
    required this.branches,
    required this.selectedBranch,
    required this.query,
    required this.controller,
    required this.errorText,
    required this.onQueryChanged,
    required this.onSelectBranch,
  });

  final List<String> branches;
  final String? selectedBranch;
  final String query;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSelectBranch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = <String>[
      for (final branch in branches)
        if (normalizedQuery.isEmpty ||
            branch.toLowerCase().contains(normalizedQuery))
          branch,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Source branch',
          style: theme.textTheme.labelMedium?.copyWith(
            color: errorText == null
                ? AleraTokens.foregroundMuted
                : AleraTokens.error,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        _SearchField(
          controller: controller,
          hintText: 'Search source branches',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          maxHeight: 144,
          child: filtered.isEmpty
              ? _EmptyPickerMessage(
                  message: 'No source branches match "$query"',
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final branch = filtered[index];
                    return _BranchOption(
                      branch: branch,
                      selected: branch == selectedBranch,
                      onTap: () => onSelectBranch(branch),
                    );
                  },
                ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(
            Icons.search,
            size: 16,
            color: AleraTokens.foregroundFaint,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({required this.child, this.maxHeight = 128});

  final Widget child;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ProjectOption extends StatelessWidget {
  const _ProjectOption({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AleraTokens.accentSubtle : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: selected
                  ? AleraTokens.accent
                  : AleraTokens.foregroundFaint,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    project.repoPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchOption extends StatelessWidget {
  const _BranchOption({
    required this.branch,
    required this.selected,
    required this.onTap,
  });

  final String branch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AleraTokens.accentSubtle : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: selected
                  ? AleraTokens.accent
                  : AleraTokens.foregroundFaint,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBranches extends StatelessWidget {
  const _LoadingBranches();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AleraTokens.space8),
          Text(
            'Loading source branches',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPickerMessage extends StatelessWidget {
  const _EmptyPickerMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundFaint),
      ),
    );
  }
}
