import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

part 'create_workspace_dialog_pickers.dart';

class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({
    super.key,
    required this.projects,
    required this.loadBranches,
    required this.onCreateWorkspace,
    required this.checkBranchExists,
    required this.getProjectActiveBranch,
    this.initialProject,
    this.onAddProject,
  });

  final List<Project> projects;
  final Project? initialProject;
  final Future<List<String>> Function(Project project) loadBranches;
  final Future<void> Function({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    String? name,
  })
  onCreateWorkspace;
  final Future<bool> Function(Project project, String branchName)
  checkBranchExists;
  final String? Function(Project project) getProjectActiveBranch;
  final VoidCallback? onAddProject;

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

  // New state fields for 2-step flow and inline creation
  int _currentStep = 1; // 1: Selection, 2: Config/Preview
  bool _creating = false;
  String? _creationError;
  Timer? _validationDebounce;
  bool _isValidatingBranch = false;
  String? _branchValidationError;

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
    _validationDebounce?.cancel();
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

  void _onNewBranchChanged(String value) {
    final trimmed = value.trim();
    if (!_nameTouched) {
      _nameController.text = trimmed;
    }
    setState(() {
      _newBranchError = null;
      _branchValidationError = null;
    });

    _validationDebounce?.cancel();
    if (trimmed.isEmpty) return;

    _validationDebounce = Timer(const Duration(milliseconds: 400), () async {
      final project = _selectedProject;
      if (project == null) return;

      setState(() => _isValidatingBranch = true);
      try {
        final exists = await widget.checkBranchExists(project, trimmed);
        if (!mounted || _newBranchController.text.trim() != trimmed) return;
        setState(() {
          if (exists) {
            _branchValidationError = 'Branch "$trimmed" already exists';
          }
          _isValidatingBranch = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isValidatingBranch = false);
      }
    });
  }

  void _submit() async {
    final project = _selectedProject;
    if (project == null) {
      return;
    }
    final sourceBranch = (_selectedSourceBranch ?? _sourceBranchController.text)
        .trim();
    final newBranchName = _newBranchController.text.trim();
    final name = _nameController.text.trim();

    final sourceBranchError = sourceBranch.isEmpty
        ? 'Source Branch Is Required'
        : null;
    final newBranchError = newBranchName.isEmpty
        ? 'New Branch Name Is Required'
        : null;

    if (sourceBranchError != null || newBranchError != null) {
      setState(() {
        _sourceBranchError = sourceBranchError;
        _newBranchError = newBranchError;
      });
      return;
    }

    if (_branchValidationError != null) {
      return; // Do not submit if validation error exists
    }

    setState(() {
      _creating = true;
      _creationError = null;
    });

    try {
      await widget.onCreateWorkspace(
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        name: name.isEmpty ? null : name,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _creationError = error.toString();
        });
      }
    }
  }

  String _slugify(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_/]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _getPreviewWorkspacePath() {
    final project = _selectedProject;
    if (project == null) return '';
    final projectSlug = _slugify(project.name);
    final displayName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _newBranchController.text.trim();
    final workspaceSlug = displayName.isNotEmpty
        ? _slugify(displayName)
        : 'workspace';
    return '~/.alera/workspaces/$projectSlug-${project.id}/$workspaceSlug';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProject = _selectedProject;

    if (widget.projects.isEmpty) {
      return AleraDialog(
        maxWidth: 440,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AleraEmptyState(
                icon: AleraIcons.folderOff,
                title: 'No Git Projects Yet',
                message:
                    'Linked workspaces require a Git project. Add one to get started.',
                action: widget.onAddProject != null
                    ? FilledButton.icon(
                        onPressed: widget.onAddProject,
                        icon: const Icon(AleraIcons.add, size: 16),
                        label: const Text('Add Git Project'),
                      )
                    : null,
              ),
              const SizedBox(height: AleraTokens.space8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    final isStep1 = _currentStep == 1;

    return AleraDialog(
      maxWidth: isStep1 ? 680 : 560,
      maxHeight: 740,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!isStep1 && !_creating) ...[
                  IconButton(
                    icon: const Icon(AleraIcons.back, size: 20),
                    color: AleraTokens.foregroundMuted,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _currentStep = 1;
                        _creationError = null;
                      });
                    },
                  ),
                  const SizedBox(width: AleraTokens.space12),
                ],
                const Icon(AleraIcons.gitFork, color: AleraTokens.accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    isStep1
                        ? 'New Workspace — Selection'
                        : 'New Workspace — Settings',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space12),
                if (_creating)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    isStep1 ? 'Step 1 of 2' : 'Step 2 of 2',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            if (_creationError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  border: Border.all(
                    color: AleraTokens.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      AleraIcons.error,
                      color: AleraTokens.error,
                      size: 16,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        _creationError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AleraTokens.space12),
            ],
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0.0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: isStep1
                    ? KeyedSubtree(
                        key: const ValueKey('step1'),
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
                                getProjectActiveBranch:
                                    widget.getProjectActiveBranch,
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
                                if (_branchesError != null) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _branchesError!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AleraTokens.error,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: AleraTokens.space8),
                                      IconButton(
                                        icon: const Icon(
                                          AleraIcons.refresh,
                                          size: 16,
                                        ),
                                        onPressed: () {
                                          if (selectedProject != null) {
                                            _loadBranches(selectedProject);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AleraTokens.space8),
                                ],
                                AleraTextField(
                                  controller: _sourceBranchController,
                                  autofocus: true,
                                  labelText: 'Source Branch',
                                  hintText: 'e.g. main',
                                  errorText: _sourceBranchError,
                                  onChanged: (_) {
                                    setState(() => _sourceBranchError = null);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('step2'),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AleraTokens.space12,
                                  vertical: AleraTokens.space8,
                                ),
                                decoration: BoxDecoration(
                                  color: AleraTokens.surfaceVariant,
                                  borderRadius: BorderRadius.circular(
                                    AleraTokens.radiusMd,
                                  ),
                                  border: Border.all(
                                    color: AleraTokens.borderSubtle,
                                  ),
                                ),
                                child: Table(
                                  columnWidths: const {
                                    0: IntrinsicColumnWidth(),
                                    1: FlexColumnWidth(),
                                  },
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
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          selectedProject?.name ?? '',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AleraTokens.foreground,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ],
                                    ),
                                    TableRow(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: AleraTokens.space12,
                                          ),
                                          child: Text(
                                            'Source Branch:',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          _selectedSourceBranch ??
                                              _sourceBranchController.text,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AleraTokens.foreground,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AleraTokens.space16),
                              AleraTextField(
                                controller: _newBranchController,
                                autofocus: true,
                                enabled: !_creating,
                                labelText: 'New Branch Name *',
                                hintText: 'e.g. feature/terminal-tabs',
                                errorText:
                                    _newBranchError ?? _branchValidationError,
                                suffix: _isValidatingBranch
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                        ),
                                      )
                                    : null,
                                onChanged: _onNewBranchChanged,
                                onSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: AleraTokens.space12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: AleraTextField(
                                      controller: _nameController,
                                      enabled: !_creating,
                                      labelText: 'Workspace Name (Optional)',
                                      onChanged: (value) {
                                        setState(() {
                                          _nameTouched = value.isNotEmpty;
                                        });
                                      },
                                      onSubmitted: (_) => _submit(),
                                    ),
                                  ),
                                  if (!_nameTouched &&
                                      _newBranchController.text.isNotEmpty) ...[
                                    const SizedBox(width: AleraTokens.space8),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: AleraTokens.space16,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AleraTokens.space6,
                                          vertical: AleraTokens.space2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AleraTokens.accentSubtle,
                                          borderRadius: BorderRadius.circular(
                                            AleraTokens.radiusSm,
                                          ),
                                          border: Border.all(
                                            color: AleraTokens.accent
                                                .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              AleraIcons.link,
                                              size: 10,
                                              color: AleraTokens.accent
                                                  .withValues(alpha: 0.7),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'sync',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    fontSize: 10,
                                                    color: AleraTokens.accent,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: AleraTokens.space16),
                              Text(
                                'Preview',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AleraTokens.foregroundMuted,
                                ),
                              ),
                              const SizedBox(height: AleraTokens.space6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  AleraTokens.space12,
                                ),
                                decoration: BoxDecoration(
                                  color: AleraTokens.surface,
                                  borderRadius: BorderRadius.circular(
                                    AleraTokens.radiusMd,
                                  ),
                                  border: Border.all(
                                    color: AleraTokens.borderSubtle,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          AleraIcons.folder,
                                          size: 14,
                                          color: AleraTokens.foregroundMuted
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _getPreviewWorkspacePath(),
                                            overflow: TextOverflow.ellipsis,
                                            style: AleraTokens.monoStyle
                                                .copyWith(
                                                  fontSize: 11,
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          AleraIcons.gitFork,
                                          size: 14,
                                          color: AleraTokens.foregroundMuted
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Branch: ${_newBranchController.text.isEmpty ? "<new-branch>" : _newBranchController.text} ← from ${(_selectedSourceBranch ?? _sourceBranchController.text).isEmpty ? "<source>" : (_selectedSourceBranch ?? _sourceBranchController.text)}',
                                            overflow: TextOverflow.ellipsis,
                                            style: AleraTokens.monoStyle
                                                .copyWith(
                                                  fontSize: 11,
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          AleraIcons.terminal,
                                          size: 14,
                                          color: AleraTokens.foregroundMuted
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Initial terminal tab will be opened',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (isStep1)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  )
                else
                  TextButton(
                    onPressed: _creating
                        ? null
                        : () {
                            setState(() {
                              _currentStep = 1;
                              _creationError = null;
                            });
                          },
                    child: const Text('Back'),
                  ),
                const SizedBox(width: AleraTokens.space8),
                if (isStep1)
                  FilledButton(
                    onPressed: selectedProject == null || _loadingBranches
                        ? null
                        : () {
                            final sourceBranch =
                                (_selectedSourceBranch ??
                                        _sourceBranchController.text)
                                    .trim();
                            if (sourceBranch.isEmpty) {
                              setState(() {
                                _sourceBranchError =
                                    'Source Branch Is Required';
                              });
                              return;
                            }
                            setState(() {
                              _currentStep = 2;
                            });
                          },
                    child: const Text('Continue'),
                  )
                else
                  FilledButton(
                    onPressed:
                        selectedProject == null ||
                            _creating ||
                            _branchValidationError != null
                        ? null
                        : () {
                            final newBranchName = _newBranchController.text
                                .trim();
                            if (newBranchName.isEmpty) {
                              setState(() {
                                _newBranchError = 'New Branch Name Is Required';
                              });
                              return;
                            }
                            _submit();
                          },
                    child: Text(_creating ? 'Creating...' : 'Create Workspace'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
