part of 'create_workspace_dialog.dart';

extension _CreateWorkspaceDialogInteractions on _CreateWorkspaceDialogState {
  void _setProjectQuery(String value) {
    _update(() => _projectQuery = value);
  }

  void _setBranchQuery(String value) {
    _update(() => _branchQuery = value);
  }

  void _onManualSourceBranchChanged(String _) {
    _update(() {
      _sourceBranchError = null;
      if (_reuseExistingBranch) {
        final branch = _sourceBranchController.text.trim();
        _newBranchController.text = branch;
        if (!_nameTouched) {
          _nameController.text = branch;
        }
      }
    });
  }

  void _onNameChanged(String value) {
    _update(() {
      _nameTouched = value.isNotEmpty;
    });
  }

  void _setParentWorkspace(String? value) {
    _update(() => _selectedParentWorkspaceId = value);
  }

  void _setCreateAnother(bool value) {
    _update(() => _createAnother = value);
  }

  void _showSelectionStep() {
    _update(() {
      _currentStep = 1;
      _creationError = null;
    });
  }

  void _continueToSettings() {
    final sourceBranch = (_selectedSourceBranch ?? _sourceBranchController.text)
        .trim();
    if (sourceBranch.isEmpty) {
      _update(() {
        _sourceBranchError = _sourceBranchRequiredError();
      });
      return;
    }
    _update(() {
      _currentStep = 2;
    });
  }

  void _submitFromButton() {
    final sourceBranch = (_selectedSourceBranch ?? _sourceBranchController.text)
        .trim();
    final targetBranch = _targetBranchName(sourceBranch);
    if (targetBranch.isEmpty) {
      _update(() {
        _newBranchError = _targetBranchRequiredError();
      });
      return;
    }
    _submit();
  }

  void _retryBranches() {
    final project = _selectedProject;
    if (project != null) {
      _loadBranches(project);
    }
  }
}
