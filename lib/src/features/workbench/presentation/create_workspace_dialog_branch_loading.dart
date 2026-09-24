part of 'create_workspace_dialog.dart';

extension _CreateWorkspaceDialogBranchLoading on _CreateWorkspaceDialogState {
  Future<String?> _preferredSourceFor(Project project) async {
    if (_preferredSourceByProject.containsKey(project.id)) {
      return _preferredSourceByProject[project.id];
    }
    String? value;
    try {
      value = await widget.loadPreferredSourceBranch?.call(project);
    } catch (_) {
      value = null;
    }
    final trimmed = value?.trim();
    final preferred = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    _preferredSourceByProject[project.id] = preferred;
    return preferred;
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

  Future<void> _loadBranches(Project project) async {
    final generation = ++_branchLoadGeneration;
    _branchesAwaitHostEnrollment = _hostEnrollmentFor(project) != .enrolled;
    if (_branchesAwaitHostEnrollment) {
      _clearBranchChoices();
      return;
    }
    final hostId = _selectedHostId;
    final preferredSource =
        (_selectedSourceBranch ?? _sourceBranchController.text).trim();
    final preferredNewBranch = _newBranchController.text.trim();
    _update(() {
      _loadingBranches = true;
      _branchesError = null;
      _branches = const <String>[];
      _localBranches = const <String>[];
      _localBranchesLoaded = false;
      _loadingLocalBranches = false;
      _branchSearchController.clear();
      _branchQuery = '';
    });
    try {
      final catalog = await widget.loadHostBranchCatalog?.call(project, hostId);
      final branches = catalog?.branches ?? await widget.loadBranches(project);
      final projectPreferred = await _preferredSourceFor(project);
      if (!mounted ||
          _selectedProject?.id != project.id ||
          _selectedHostId != hostId ||
          generation != _branchLoadGeneration) {
        return;
      }
      _projectPreferredSource = projectPreferred;
      final selected =
          preferredSource.isNotEmpty && branches.contains(preferredSource)
          ? preferredSource
          : _pickDefaultSourceBranch(
              _reuseExistingBranch ? const <String>[] : branches,
              useProjectPreference: !_reuseExistingBranch,
            );
      _update(() {
        _branches = branches;
        _selectedSourceBranch = selected;
        if (selected != null) {
          _sourceBranchController.text = selected;
          if (_reuseExistingBranch && preferredNewBranch.isEmpty) {
            _newBranchController.text = selected;
            if (!_nameTouched) {
              _nameController.text = selected;
            }
          }
        }
        if (preferredNewBranch.isNotEmpty && !_reuseExistingBranch) {
          _newBranchController.text = preferredNewBranch;
        }
        _loadingBranches = false;
      });
      if (_reuseExistingBranch) {
        unawaited(_loadLocalBranches(project));
      }
    } catch (error) {
      if (!mounted ||
          _selectedProject?.id != project.id ||
          _selectedHostId != hostId ||
          generation != _branchLoadGeneration) {
        return;
      }
      _update(() {
        _branchesError = error.toString();
        _loadingBranches = false;
      });
    }
  }

  /// A host the project is not on has no branch catalog to ask for, so the
  /// request would only flash a runtime error over the "Add to Host" notice.
  void _clearBranchChoices() {
    _update(() {
      _loadingBranches = false;
      _branchesError = null;
      _branches = const <String>[];
      _localBranches = const <String>[];
      _localBranchesLoaded = false;
      _loadingLocalBranches = false;
      _branchSearchController.clear();
      _branchQuery = '';
    });
  }

  Future<void> _loadLocalBranches(Project project) async {
    if (_localBranchesLoaded ||
        _loadingLocalBranches ||
        _loadingBranches ||
        _hostEnrollmentFor(project) != .enrolled) {
      return;
    }
    _update(() {
      _loadingLocalBranches = true;
    });
    final hostId = _selectedHostId;
    final generation = _branchLoadGeneration;
    final List<String> localBranches;
    try {
      localBranches = await _filterLocalBranches(project, _branches);
    } catch (error) {
      if (mounted &&
          generation == _branchLoadGeneration &&
          _selectedHostId == hostId) {
        _update(() {
          _loadingLocalBranches = false;
          _branchesError = error.toString();
        });
      }
      return;
    }
    if (!mounted ||
        _selectedProject?.id != project.id ||
        _selectedHostId != hostId ||
        generation != _branchLoadGeneration) {
      return;
    }
    final preferredSource =
        (_selectedSourceBranch ?? _sourceBranchController.text).trim();
    final preferredNewBranch = _newBranchController.text.trim();
    final selectedBranch = _reuseExistingBranch
        ? (preferredSource.isNotEmpty && localBranches.contains(preferredSource)
              ? preferredSource
              : _pickDefaultSourceBranch(
                  localBranches,
                  useProjectPreference: false,
                ))
        : _selectedSourceBranch;
    _update(() {
      _localBranches = localBranches;
      _localBranchesLoaded = true;
      _loadingLocalBranches = false;
      if (_reuseExistingBranch) {
        _selectedSourceBranch = selectedBranch;
        if (selectedBranch == null) {
          _sourceBranchController.clear();
          if (preferredNewBranch.isEmpty) {
            _newBranchController.clear();
          }
          if (!_nameTouched) {
            _nameController.clear();
          }
        } else {
          _sourceBranchController.text = selectedBranch;
          if (preferredNewBranch.isEmpty) {
            _newBranchController.text = selectedBranch;
          }
          if (!_nameTouched) {
            _nameController.text = selectedBranch;
          }
        }
      }
    });
  }
}
