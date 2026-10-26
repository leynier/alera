part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogBranchLoading on _PromptWorkspaceDialogState {
  /// Loads the branch catalog for the selected host. [preserveBranch] keeps
  /// the branch picked on the previous host selected when the new catalog has
  /// it too.
  Future<void> _loadBranches(Project project, {String? preserveBranch}) async {
    final hostId = _selectedHostId;
    final generation = ++_branchLoadGeneration;
    // A host the project is not on has no branch catalog to ask for.
    _branchesAwaitHostEnrollment = _hostEnrollmentFor(project) != .enrolled;
    if (_branchesAwaitHostEnrollment) {
      _update(() {
        _loadingBranches = false;
        _branches = const <String>[];
        _sourceBranch = null;
      });
      return;
    }
    _update(() {
      _loadingBranches = true;
      if (_error != widget.initialError) {
        _error = null;
      }
      _branches = const <String>[];
      _sourceBranch = null;
    });
    try {
      final catalog = await widget.loadHostBranchCatalog?.call(project, hostId);
      final branches = catalog?.branches ?? await widget.loadBranches(project);
      final projectPreferred = await _preferredSourceFor(project);
      if (!mounted ||
          _project?.id != project.id ||
          _selectedHostId != hostId ||
          generation != _branchLoadGeneration) {
        return;
      }
      _update(() {
        _branches = branches;
        final preferred =
            preserveBranch ??
            (project.id == widget.initialProject?.id
                ? widget.initialSourceBranch
                : null);
        _sourceBranch = (preferred != null && branches.contains(preferred)
            ? preferred
            : pickDefaultSourceBranch(branches, preferred: projectPreferred));
        _loadingBranches = false;
      });
    } catch (error) {
      if (mounted &&
          _project?.id == project.id &&
          _selectedHostId == hostId &&
          generation == _branchLoadGeneration) {
        _update(() {
          _loadingBranches = false;
          _sourceBranch = null;
          _error = userFacingErrorMessage(error);
        });
      }
    }
  }
}
