import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

part 'create_workspace_dialog_pickers.dart';

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
