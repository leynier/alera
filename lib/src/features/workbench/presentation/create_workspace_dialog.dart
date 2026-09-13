import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_branch_catalog.dart';
import 'package:alera/src/features/projects/domain/project_selection_order.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_parent_selection_order.dart';
import 'package:alera/src/features/workbench/presentation/workspace_host_picker.dart';
import 'package:flutter/material.dart';

part 'create_workspace_dialog_pickers.dart';
part 'create_workspace_dialog_branch_loading.dart';
part 'create_workspace_dialog_frame.dart';
part 'create_workspace_dialog_interactions.dart';
part 'create_workspace_dialog_selection_order.dart';
part 'create_workspace_dialog_selection_step.dart';
part 'create_workspace_dialog_settings_step.dart';
part 'create_workspace_dialog_submission.dart';

class const CreateWorkspaceDialog({
  super.key,
  required final List<Project> projects,
  required final Future<List<String>> Function(Project project) loadBranches,
  final Future<ProjectBranchCatalog> Function(Project project, String? hostId)?
  loadHostBranchCatalog,
  required final Future<WorkspaceCreationResult> Function({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    String? name,
    String? parentWorkspaceId,
    String? hostId,
  })
  onCreateWorkspace,
  required final Future<bool> Function(Project project, String branchName)
  checkBranchExists,
  required final String? Function(Project project) getProjectActiveBranch,
  required final Set<String> Function(Project project)
  getProjectWorkspaceBranches,
  final List<WorkspaceParentCandidate> parentCandidates =
      const <WorkspaceParentCandidate>[],
  final Project? initialProject,
  final VoidCallback? onAddProject,
  final ValueChanged<WorkspaceCreationResult>? onWorkspaceCreated,
  final Future<void>? Function(ManualWorkspaceCreateRequest request)?
  enqueueCreate,
  final bool initialUseProjectCheckout = true,
  final List<SshTarget> sshTargets = const <SshTarget>[],
  final bool supportsRemoteSshWorkspaces = true,
  final String? initialSourceBranch,
  final String? initialNewBranchName,
  final String? initialName,
  final String? initialParentWorkspaceId,
  final String? initialHostId,
  final bool initialReuseExistingBranch = false,
  final String? initialCreationError,
  final bool embedded = false,
}) extends StatefulWidget {
  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class const WorkspaceParentCandidate({
  required final Project project,
  required final Workspace workspace,
});

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
  String? _selectedHostId;
  int _branchLoadGeneration = 0;
  bool _reuseExistingBranch = false;
  bool _createAnother = false;
  bool _useProjectCheckout = false;

  // New state fields for 2-step flow and inline creation
  int _currentStep = 1; // 1: Selection, 2: Config/Preview
  bool _creating = false;
  String? _creationError;
  Timer? _validationDebounce;
  bool _isValidatingBranch = false;
  String? _branchValidationError;

  void _update(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    _useProjectCheckout =
        widget.enqueueCreate != null && widget.initialUseProjectCheckout;
    _selectedProject = _pickInitialProject();
    _selectedParentWorkspaceId = widget.initialParentWorkspaceId;
    _selectedHostId = widget.initialHostId;
    _reuseExistingBranch = widget.initialReuseExistingBranch;
    _creationError = widget.initialCreationError;
    final initialName = widget.initialName?.trim();
    if (initialName != null && initialName.isNotEmpty) {
      _nameController.text = initialName;
      _nameTouched = true;
    }
    final initialBranch = widget.initialNewBranchName?.trim();
    if (initialBranch != null && initialBranch.isNotEmpty) {
      _newBranchController.text = initialBranch;
    }
    final initialSource = widget.initialSourceBranch?.trim();
    if (initialSource != null && initialSource.isNotEmpty) {
      _selectedSourceBranch = initialSource;
      _sourceBranchController.text = initialSource;
    }
    if (widget.initialCreationError != null ||
        (widget.initialNewBranchName?.trim().isNotEmpty ?? false)) {
      _currentStep = 2;
    }
    final project = _selectedProject;
    if (project != null) {
      if (!_useProjectCheckout) _loadBranches(project);
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
      for (final project in _orderedProjects) {
        if (project.id == initial.id) {
          return project;
        }
      }
    }
    return _orderedProjects.firstOrNull;
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
    final hostId = _selectedHostId;
    final catalog = await widget.loadHostBranchCatalog?.call(project, hostId);
    final workspaceBranches =
        (catalog == null
                ? widget.getProjectWorkspaceBranches(project)
                : widget.parentCandidates
                      .map((candidate) => candidate.workspace)
                      .where(
                        (workspace) =>
                            workspace.projectId == project.id &&
                            workspace.hostId == (hostId ?? 'local'),
                      )
                      .map((workspace) => workspace.branch ?? ''))
            .map((branch) => branch.trim())
            .where((branch) => branch.isNotEmpty)
            .toSet();
    final results = await Future.wait(
      branches.map((branch) async {
        try {
          return (
            branch: branch,
            isLocal:
                catalog?.localBranches.contains(branch) ??
                await widget.checkBranchExists(project, branch),
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

  String? _pickBranchForMode(bool reuseExistingBranch) {
    final availableBranches = _branchesForMode(reuseExistingBranch);
    final currentBranch =
        (_selectedSourceBranch ?? _sourceBranchController.text).trim();
    if (currentBranch.isNotEmpty && availableBranches.contains(currentBranch)) {
      return currentBranch;
    }
    return _pickDefaultSourceBranch(availableBranches);
  }

  void _selectProject(Project project) {
    if (_selectedProject?.id == project.id) {
      return;
    }
    setState(() {
      _selectedProject = project;
      _sourceBranchError = null;
      if (!project.isGitRepository && widget.enqueueCreate != null) {
        _useProjectCheckout = true;
      }
    });
    if (!_useProjectCheckout) _loadBranches(project);
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

      final hostId = _selectedHostId;
      setState(() => _isValidatingBranch = true);
      try {
        final catalog = await widget.loadHostBranchCatalog?.call(
          project,
          hostId,
        );
        final exists =
            catalog?.localBranches.contains(trimmed) ??
            await widget.checkBranchExists(project, trimmed);
        if (!mounted ||
            _selectedHostId != hostId ||
            _newBranchController.text.trim() != trimmed) {
          return;
        }
        setState(() {
          if (_reuseExistingBranch && !exists) {
            _branchValidationError = 'Branch "$trimmed" does not exist';
          } else if (!_reuseExistingBranch && exists) {
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

  String _targetBranchName(String sourceBranch) {
    if (_reuseExistingBranch) {
      return sourceBranch;
    }
    return _newBranchController.text.trim();
  }

  String _sourceBranchRequiredError() {
    return _reuseExistingBranch
        ? 'Existing branch is required'
        : 'Source branch is required';
  }

  String _targetBranchRequiredError() {
    return _reuseExistingBranch
        ? 'Existing branch is required'
        : 'New branch name is required';
  }

  @override
  Widget build(BuildContext context) {
    final selectedProject = _selectedProject;
    if (widget.projects.isEmpty) {
      return _EmptyProjectsDialog(
        embedded: widget.embedded,
        onAddProject: widget.onAddProject,
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    final isSelectionStep = _currentStep == 1;
    final sourceBranch = _selectedSourceBranch ?? _sourceBranchController.text;
    final step = isSelectionStep
        ? _CreateWorkspaceSelectionStep(
            useProjectCheckout: _useProjectCheckout,
            onLocationChanged: widget.enqueueCreate == null
                ? null
                : _setProjectCheckout,
            projects: _orderedProjects,
            selectedProject: selectedProject,
            projectQuery: _projectQuery,
            projectSearchController: _projectSearchController,
            onProjectQueryChanged: _setProjectQuery,
            onSelectProject: _selectProject,
            getProjectActiveBranch: widget.getProjectActiveBranch,
            reuseExistingBranch: _reuseExistingBranch,
            onReuseExistingBranchChanged: _setReuseExistingBranch,
            loadingBranches:
                _loadingBranches ||
                (_reuseExistingBranch && _loadingLocalBranches),
            branches: _branchesForMode(_reuseExistingBranch),
            selectedBranch: _selectedSourceBranch,
            branchQuery: _branchQuery,
            branchSearchController: _branchSearchController,
            onBranchQueryChanged: _setBranchQuery,
            onSelectBranch: _selectSourceBranch,
            branchesError: _branchesError,
            onRetryBranches: _retryBranches,
            sourceBranchController: _sourceBranchController,
            sourceBranchError: _sourceBranchError,
            onManualSourceBranchChanged: _onManualSourceBranchChanged,
          )
        : _CreateWorkspaceSettingsStep(
            useProjectCheckout: _useProjectCheckout,
            project: selectedProject,
            sourceBranch: sourceBranch,
            reuseExistingBranch: _reuseExistingBranch,
            newBranchController: _newBranchController,
            newBranchError: _newBranchError,
            branchValidationError: _branchValidationError,
            isValidatingBranch: _isValidatingBranch,
            onNewBranchChanged: _onNewBranchChanged,
            nameController: _nameController,
            nameTouched: _nameTouched,
            onNameChanged: _onNameChanged,
            parentCandidates: _parentCandidates,
            selectedParentWorkspaceId: _selectedParentWorkspaceId,
            onParentWorkspaceChanged: _setParentWorkspace,
            sshTargets: widget.sshTargets,
            selectedHostId: _selectedHostId,
            supportsRemoteSshWorkspaces: widget.supportsRemoteSshWorkspaces,
            onHostChanged: _setHost,
            creating: _creating,
            onSubmit: _submit,
          );

    return _CreateWorkspaceDialogFrame(
      embedded: widget.embedded,
      isSelectionStep: isSelectionStep,
      creating: _creating,
      creationError: _creationError,
      step: step,
      createAnother: _createAnother,
      onCreateAnotherChanged: _setCreateAnother,
      onCancel: () => Navigator.of(context).pop(),
      onBack: _showSelectionStep,
      onContinue:
          selectedProject == null || (!_useProjectCheckout && _loadingBranches)
          ? null
          : _continueToSettings,
      onCreate:
          selectedProject == null || _creating || _branchValidationError != null
          ? null
          : _submitFromButton,
    );
  }
}
