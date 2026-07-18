import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
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
    required this.getProjectWorkspaceBranches,
    this.parentCandidates = const <WorkspaceParentCandidate>[],
    this.initialProject,
    this.onAddProject,
  });

  final List<Project> projects;
  final Project? initialProject;
  final Future<List<String>> Function(Project project) loadBranches;
  final Future<WorkspaceCreationResult> Function({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    String? name,
    String? parentWorkspaceId,
  })
  onCreateWorkspace;
  final Future<bool> Function(Project project, String branchName)
  checkBranchExists;
  final String? Function(Project project) getProjectActiveBranch;
  final Set<String> Function(Project project) getProjectWorkspaceBranches;
  final List<WorkspaceParentCandidate> parentCandidates;
  final VoidCallback? onAddProject;

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class WorkspaceParentCandidate {
  const WorkspaceParentCandidate({
    required this.project,
    required this.workspace,
  });

  final Project project;
  final Workspace workspace;
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
  List<String> _localBranches = const <String>[];
  bool _localBranchesLoaded = false;
  bool _loadingLocalBranches = false;
  String? _selectedSourceBranch;
  bool _nameTouched = false;
  bool _loadingBranches = false;
  String? _branchesError;
  String _projectQuery = '';
  String _branchQuery = '';
  String? _sourceBranchError;
  String? _newBranchError;
  String? _selectedParentWorkspaceId;
  bool _reuseExistingBranch = false;

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

  Future<List<String>> _filterLocalBranches(
    Project project,
    List<String> branches,
  ) async {
    final workspaceBranches = widget
        .getProjectWorkspaceBranches(project)
        .map((branch) => branch.trim())
        .where((branch) => branch.isNotEmpty)
        .toSet();
    final results = await Future.wait(
      branches.map((branch) async {
        try {
          return (
            branch: branch,
            isLocal: await widget.checkBranchExists(project, branch),
          );
        } catch (_) {
          return (branch: branch, isLocal: false);
        }
      }),
    );
    return <String>[
      for (final result in results)
        if (result.isLocal && !workspaceBranches.contains(result.branch))
          result.branch,
    ];
  }

  List<String> _branchesForMode(bool reuseExistingBranch) {
    return reuseExistingBranch ? _localBranches : _branches;
  }

  List<WorkspaceParentCandidate> get _parentCandidates {
    return <WorkspaceParentCandidate>[
      for (final candidate in widget.parentCandidates)
        if (candidate.workspace.status == WorkspaceStatus.active) candidate,
    ];
  }

  String _parentLabel(WorkspaceParentCandidate candidate) {
    final branch = candidate.workspace.branch;
    final suffix = branch == null || branch.isEmpty ? '' : ' - $branch';
    return '${candidate.project.name} / ${candidate.workspace.name}$suffix';
  }

  String? _selectedParentLabel() {
    final selectedId = _selectedParentWorkspaceId;
    if (selectedId == null) {
      return null;
    }
    for (final candidate in _parentCandidates) {
      if (candidate.workspace.id == selectedId) {
        return _parentLabel(candidate);
      }
    }
    return null;
  }

  String? _pickBranchForMode(bool reuseExistingBranch) {
    final availableBranches = _branchesForMode(reuseExistingBranch);
    final currentBranch =
        (_selectedSourceBranch ?? _sourceBranchController.text).trim();
    if (currentBranch.isNotEmpty && availableBranches.contains(currentBranch)) {
      return currentBranch;
    }
    return _pickDefaultSourceBranch(availableBranches);
  }

  Future<void> _loadBranches(Project project) async {
    setState(() {
      _loadingBranches = true;
      _branchesError = null;
      _branches = const <String>[];
      _localBranches = const <String>[];
      _localBranchesLoaded = false;
      _loadingLocalBranches = false;
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
      final defaultBranch = _pickDefaultSourceBranch(
        _reuseExistingBranch ? const <String>[] : branches,
      );
      setState(() {
        _branches = branches;
        _selectedSourceBranch = defaultBranch;
        if (defaultBranch != null) {
          _sourceBranchController.text = defaultBranch;
          if (_reuseExistingBranch) {
            _newBranchController.text = defaultBranch;
            if (!_nameTouched) {
              _nameController.text = defaultBranch;
            }
          }
        }
        _loadingBranches = false;
      });
      if (_reuseExistingBranch) {
        unawaited(_loadLocalBranches(project));
      }
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

  Future<void> _loadLocalBranches(Project project) async {
    if (_localBranchesLoaded || _loadingLocalBranches || _loadingBranches) {
      return;
    }
    setState(() {
      _loadingLocalBranches = true;
    });
    final localBranches = await _filterLocalBranches(project, _branches);
    if (!mounted || _selectedProject?.id != project.id) {
      return;
    }
    final selectedBranch = _reuseExistingBranch
        ? _pickDefaultSourceBranch(localBranches)
        : _selectedSourceBranch;
    setState(() {
      _localBranches = localBranches;
      _localBranchesLoaded = true;
      _loadingLocalBranches = false;
      if (_reuseExistingBranch) {
        _selectedSourceBranch = selectedBranch;
        if (selectedBranch == null) {
          _sourceBranchController.clear();
          _newBranchController.clear();
          if (!_nameTouched) {
            _nameController.clear();
          }
        } else {
          _sourceBranchController.text = selectedBranch;
          _newBranchController.text = selectedBranch;
          if (!_nameTouched) {
            _nameController.text = selectedBranch;
          }
        }
      }
    });
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
      if (_reuseExistingBranch) {
        _newBranchController.text = branch;
        if (!_nameTouched) {
          _nameController.text = branch;
        }
      }
    });
  }

  void _setReuseExistingBranch(bool value) {
    if (_reuseExistingBranch == value) {
      return;
    }
    _validationDebounce?.cancel();
    final selectedBranch = value && !_localBranchesLoaded
        ? null
        : _pickBranchForMode(value);
    setState(() {
      _reuseExistingBranch = value;
      _selectedSourceBranch = selectedBranch;
      _sourceBranchError = null;
      _newBranchError = null;
      _branchValidationError = null;
      _isValidatingBranch = false;
      _branchSearchController.clear();
      _branchQuery = '';
      if (selectedBranch == null) {
        _sourceBranchController.clear();
      } else {
        _sourceBranchController.text = selectedBranch;
      }
      if (value) {
        _newBranchController.text = selectedBranch ?? '';
        if (!_nameTouched) {
          _nameController.text = selectedBranch ?? '';
        }
      } else {
        _newBranchController.clear();
        if (!_nameTouched) {
          _nameController.clear();
        }
      }
    });
    if (value) {
      final project = _selectedProject;
      if (project != null) {
        unawaited(_loadLocalBranches(project));
      }
    }
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
          if (_reuseExistingBranch && !exists) {
            _branchValidationError = 'Branch "$trimmed" Does Not Exist';
          } else if (!_reuseExistingBranch && exists) {
            _branchValidationError = 'Branch "$trimmed" Already Exists';
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
    final newBranchName = _targetBranchName(sourceBranch);
    final name = _nameController.text.trim();

    final sourceBranchError = sourceBranch.isEmpty
        ? _sourceBranchRequiredError()
        : null;
    final newBranchError = newBranchName.isEmpty
        ? _targetBranchRequiredError()
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
      final result = await widget.onCreateWorkspace(
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        reuseExistingBranch: _reuseExistingBranch,
        name: name.isEmpty ? null : name,
        parentWorkspaceId: _selectedParentWorkspaceId,
      );
      if (mounted) {
        Navigator.of(context).pop(result);
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

  String _targetBranchName(String sourceBranch) {
    if (_reuseExistingBranch) {
      return sourceBranch;
    }
    return _newBranchController.text.trim();
  }

  String _sourceBranchRequiredError() {
    return _reuseExistingBranch
        ? 'Existing Branch Is Required'
        : 'Source Branch Is Required';
  }

  String _targetBranchRequiredError() {
    return _reuseExistingBranch
        ? 'Existing Branch Is Required'
        : 'New Branch Name Is Required';
  }

  String _branchPickerLabel() {
    return _reuseExistingBranch ? 'Existing Branch' : 'Source Branch';
  }

  String _branchSearchHint() {
    return _reuseExistingBranch
        ? 'Search Existing Branches'
        : 'Search Source Branches';
  }

  String _emptyBranchesMessage() {
    return _reuseExistingBranch
        ? 'No Existing Branches Match "$_branchQuery"'
        : 'No Source Branches Match "$_branchQuery"';
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
    final visibleBranches = _branchesForMode(_reuseExistingBranch);
    final loadingBranchChoices =
        _loadingBranches || (_reuseExistingBranch && _loadingLocalBranches);

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
                        ? 'New Workspace - Selection'
                        : 'New Workspace - Settings',
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
                duration: AleraTokens.durationMid,
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
                              AleraSegmentedButton<bool>(
                                segments: const <ButtonSegment<bool>>[
                                  ButtonSegment<bool>(
                                    value: false,
                                    label: Text('New Branch'),
                                  ),
                                  ButtonSegment<bool>(
                                    value: true,
                                    label: Text('Existing Branch'),
                                  ),
                                ],
                                selected: _reuseExistingBranch,
                                onSelectionChanged: _setReuseExistingBranch,
                              ),
                              const SizedBox(height: AleraTokens.space16),
                              if (loadingBranchChoices)
                                const _LoadingBranches()
                              else if (visibleBranches.isNotEmpty)
                                _SourceBranchPicker(
                                  label: _branchPickerLabel(),
                                  searchHint: _branchSearchHint(),
                                  emptyMessage: _emptyBranchesMessage(),
                                  branches: visibleBranches,
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
                                  labelText: _branchPickerLabel(),
                                  hintText: 'e.g. main',
                                  errorText: _sourceBranchError,
                                  onChanged: (_) {
                                    setState(() {
                                      _sourceBranchError = null;
                                      if (_reuseExistingBranch) {
                                        final branch = _sourceBranchController
                                            .text
                                            .trim();
                                        _newBranchController.text = branch;
                                        if (!_nameTouched) {
                                          _nameController.text = branch;
                                        }
                                      }
                                    });
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
                                            _reuseExistingBranch
                                                ? 'Existing Branch:'
                                                : 'Source Branch:',
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
                              if (_reuseExistingBranch)
                                AleraTextField(
                                  controller: _newBranchController,
                                  enabled: false,
                                  labelText: 'Existing Branch *',
                                  errorText: _newBranchError,
                                )
                              else
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
                                            const SizedBox(
                                              width: AleraTokens.space4,
                                            ),
                                            Text(
                                              'Sync',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
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
                              AleraDropdownField<String?>(
                                value: _selectedParentWorkspaceId,
                                labelText: 'Parent Workspace',
                                enabled: !_creating,
                                entries: <AleraDropdownFieldEntry<String?>>[
                                  const AleraDropdownFieldEntry<String?>(
                                    value: null,
                                    label: 'No Parent',
                                  ),
                                  for (final candidate in _parentCandidates)
                                    AleraDropdownFieldEntry<String?>(
                                      value: candidate.workspace.id,
                                      label: _parentLabel(candidate),
                                    ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedParentWorkspaceId = value;
                                  });
                                },
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
                                        const SizedBox(
                                          width: AleraTokens.space6,
                                        ),
                                        Expanded(
                                          child: Text(
                                            _getPreviewWorkspacePath(),
                                            overflow: TextOverflow.ellipsis,
                                            style: AleraTokens.monoStyle
                                                .copyWith(
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AleraTokens.space6),
                                    Row(
                                      children: [
                                        Icon(
                                          AleraIcons.gitFork,
                                          size: 14,
                                          color: AleraTokens.foregroundMuted
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(
                                          width: AleraTokens.space6,
                                        ),
                                        Expanded(
                                          child: Text(
                                            _reuseExistingBranch
                                                ? 'Branch: ${(_selectedSourceBranch ?? _sourceBranchController.text).isEmpty ? "<existing-branch>" : (_selectedSourceBranch ?? _sourceBranchController.text)}'
                                                : 'Branch: ${_newBranchController.text.isEmpty ? "<new-branch>" : _newBranchController.text} ← from ${(_selectedSourceBranch ?? _sourceBranchController.text).isEmpty ? "<source>" : (_selectedSourceBranch ?? _sourceBranchController.text)}',
                                            overflow: TextOverflow.ellipsis,
                                            style: AleraTokens.monoStyle
                                                .copyWith(
                                                  color: AleraTokens
                                                      .foregroundMuted,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_selectedParentLabel()
                                        case final parentLabel?) ...[
                                      const SizedBox(
                                        height: AleraTokens.space6,
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            AleraIcons.link,
                                            size: 14,
                                            color: AleraTokens.foregroundMuted
                                                .withValues(alpha: 0.7),
                                          ),
                                          const SizedBox(
                                            width: AleraTokens.space6,
                                          ),
                                          Expanded(
                                            child: Text(
                                              'Parent: $parentLabel',
                                              overflow: TextOverflow.ellipsis,
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
                                    const SizedBox(height: AleraTokens.space6),
                                    Row(
                                      children: [
                                        Icon(
                                          AleraIcons.terminal,
                                          size: 14,
                                          color: AleraTokens.foregroundMuted
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(
                                          width: AleraTokens.space6,
                                        ),
                                        Expanded(
                                          child: Text(
                                            'Initial Terminal Tab Will Be Opened',
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
                                    _sourceBranchRequiredError();
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
                            final sourceBranch =
                                (_selectedSourceBranch ??
                                        _sourceBranchController.text)
                                    .trim();
                            final targetBranch = _targetBranchName(
                              sourceBranch,
                            );
                            if (targetBranch.isEmpty) {
                              setState(() {
                                _newBranchError = _targetBranchRequiredError();
                              });
                              return;
                            }
                            _submit();
                          },
                    child: Text(_creating ? 'Creating…' : 'Create Workspace'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
