part of 'create_workspace_dialog.dart';

extension _CreateWorkspaceDialogInteractions on _CreateWorkspaceDialogState {
  void _setProjectCheckout(bool value) {
    _validationDebounce?.cancel();
    _update(() {
      _useProjectCheckout = value;
      _sourceBranchError = null;
      _newBranchError = null;
      _branchValidationError = null;
      _isValidatingBranch = false;
      if (!_nameTouched) _nameController.clear();
    });
    final project = _selectedProject;
    if (!value && project != null) unawaited(_loadBranches(project));
  }

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
      _nameFromIssue = false;
    });
  }

  void _setParentWorkspace(String? value) {
    _update(() => _selectedParentWorkspaceId = value);
  }

  void _setHost(String? value) {
    _validationDebounce?.cancel();
    _update(() {
      _selectedHostId = value;
      _isValidatingBranch = false;
      _branchValidationError = null;
      _selectedSourceBranch = null;
      _sourceBranchController.clear();
      _creationError = null;
    });
    final project = _selectedProject;
    if (!_useProjectCheckout && project != null) {
      unawaited(_loadBranches(project));
    }
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
    if (!_useProjectCheckout && sourceBranch.isEmpty) {
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
    if (!_useProjectCheckout && targetBranch.isEmpty) {
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
