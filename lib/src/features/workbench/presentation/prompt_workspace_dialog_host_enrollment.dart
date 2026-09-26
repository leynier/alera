part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogHostEnrollment on _PromptWorkspaceDialogState {
  ProjectHostEnrollment _hostEnrollmentFor(Project project) {
    return projectHostEnrollment(
      project: _hostEnrollment.resolve(project),
      hostId: _selectedHostId,
      supportsProjectHosts: _hostEnrollment.supported,
    );
  }

  /// Create stays off while the project has no checkout on the selected host,
  /// and while one is being added: the request can outlive a host change.
  bool get _hostBlocksCreation {
    final project = _project;
    return _hostEnrollment.adding ||
        (project != null && _hostEnrollmentFor(project) != .enrolled);
  }

  /// The controller is shared with the other New Workspace form, so the add
  /// that puts the project on this form's host may have been started there.
  void _onHostEnrollmentChanged() {
    if (!mounted) {
      return;
    }
    final project = _project;
    _update(() {
      if (project != null) {
        _project = _hostEnrollment.resolve(project);
      }
    });
    if (project != null &&
        _branchesAwaitHostEnrollment &&
        !_useProjectCheckout &&
        _hostEnrollmentFor(project) == .enrolled) {
      unawaited(_loadBranches(_hostEnrollment.resolve(project)));
    }
  }

  void _addProjectToSelectedHost() {
    final project = _project;
    final hostId = normalizedRemoteHostId(_selectedHostId);
    if (project != null && hostId != null) {
      unawaited(_hostEnrollment.add(project, hostId));
    }
  }

  Widget? _hostEnrollmentNotice() {
    final project = _project;
    if (project == null) {
      return null;
    }
    final enrollment = _hostEnrollmentFor(project);
    if (enrollment == .enrolled) {
      return null;
    }
    return ProjectHostEnrollmentNotice(
      enrollment: enrollment,
      projectName: project.name,
      hostLabel: workspaceHostLabel(widget.sshTargets, _selectedHostId),
      controller: _hostEnrollment,
      enabled: !_working && _created == null,
      onAdd: _addProjectToSelectedHost,
    );
  }
}
