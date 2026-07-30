part of 'create_workspace_dialog.dart';

extension _CreateWorkspaceDialogSubmission on _CreateWorkspaceDialogState {
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
      _update(() {
        _sourceBranchError = sourceBranchError;
        _newBranchError = newBranchError;
      });
      return;
    }

    if (_branchValidationError != null) {
      return;
    }

    _update(() {
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
      if (!mounted) {
        return;
      }
      if (_createAnother) {
        widget.onWorkspaceCreated?.call(result);
        _resetAfterCreation(project);
      } else {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (mounted) {
        _update(() {
          _creating = false;
          _creationError = error.toString();
        });
      }
    }
  }

  void _resetAfterCreation(Project project) {
    _validationDebounce?.cancel();
    _branchSearchController.clear();
    _sourceBranchController.clear();
    _newBranchController.clear();
    _nameController.clear();
    _update(() {
      _selectedParentWorkspaceId = null;
      _reuseExistingBranch = false;
      _nameTouched = false;
      _creating = false;
      _creationError = null;
      _sourceBranchError = null;
      _newBranchError = null;
      _branchValidationError = null;
      _isValidatingBranch = false;
    });
    unawaited(_loadBranches(project));
  }
}
