import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
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
    return AleraDialog(
      maxWidth: 680,
      maxHeight: 720,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.account_tree_outlined,
                  color: AleraTokens.accent,
                ),
                const SizedBox(width: AleraTokens.space8),
                Text('New workspace', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AleraTokens.space20),
            Flexible(
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
                      AleraTextField(
                        controller: _sourceBranchController,
                        autofocus: true,
                        labelText: 'Source branch',
                        hintText: 'e.g. main',
                        errorText: _sourceBranchError,
                        onChanged: (_) {
                          setState(() => _sourceBranchError = null);
                        },
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: AleraTokens.space12),
                    AleraTextField(
                      controller: _newBranchController,
                      autofocus: _branches.isNotEmpty,
                      labelText: 'New branch name',
                      hintText: 'e.g. feature/terminal-tabs',
                      errorText: _newBranchError,
                      onChanged: (value) {
                        if (!_nameTouched) {
                          _nameController.text = value.trim();
                        }
                        setState(() => _newBranchError = null);
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    AleraTextField(
                      controller: _nameController,
                      labelText: 'Workspace name (optional)',
                      onChanged: (_) => _nameTouched = true,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    AleraPanel(
                      borderRadius: AleraTokens.radiusMd,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(AleraTokens.space12),
                          child: Text(
                            'Alera will create a new git worktree from the '
                            'selected source branch and open it as a workspace '
                            'with an initial terminal tab.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: selectedProject == null || _loadingBranches
                      ? null
                      : _submit,
                  child: const Text('Create workspace'),
                ),
              ],
            ),
          ],
        ),
      ),
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
        AleraSearchField(
          controller: controller,
          hintText: 'Search projects',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          maxHeight: 128,
          isEmpty: filtered.isEmpty,
          emptyMessage: 'No projects match "$query"',
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final project = filtered[index];
            final selected = project.id == selectedProject?.id;
            return AleraMenuItem(
              label: project.name,
              subtitle: project.repoPath,
              selected: selected,
              leading: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: selected
                    ? AleraTokens.accent
                    : AleraTokens.foregroundFaint,
              ),
              onTap: () => onSelectProject(project),
            );
          },
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
    required this.onQueryChanged,
    required this.onSelectBranch,
  });

  final List<String> branches;
  final String? selectedBranch;
  final String query;
  final TextEditingController controller;
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
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraSearchField(
          controller: controller,
          hintText: 'Search source branches',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          maxHeight: 144,
          isEmpty: filtered.isEmpty,
          emptyMessage: 'No source branches match "$query"',
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final branch = filtered[index];
            final selected = branch == selectedBranch;
            return AleraMenuItem(
              label: branch,
              selected: selected,
              leading: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: selected
                    ? AleraTokens.accent
                    : AleraTokens.foregroundFaint,
              ),
              onTap: () => onSelectBranch(branch),
            );
          },
        ),
      ],
    );
  }
}

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({
    required this.maxHeight,
    required this.isEmpty,
    required this.emptyMessage,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double maxHeight;
  final bool isEmpty;
  final String emptyMessage;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AleraTokens.radiusMd);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: radius,
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: isEmpty
          ? AleraEmptyState(message: emptyMessage)
          : ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
    );
  }
}

class _LoadingBranches extends StatelessWidget {
  const _LoadingBranches();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraPanel(
      borderRadius: AleraTokens.radiusMd,
      children: <Widget>[
        Container(
          height: 72,
          alignment: Alignment.center,
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
        ),
      ],
    );
  }
}
