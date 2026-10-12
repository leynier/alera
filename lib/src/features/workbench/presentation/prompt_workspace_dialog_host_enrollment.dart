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
        (project != null && _hostEnrollmentFor(project) != .enrolled) ||
        remoteHostSelectionError(
              hostId: _selectedHostId,
              hosts: widget.hosts,
              supportsRemoteSshWorkspaces: widget.supportsRemoteSshWorkspaces,
            ) !=
            null;
  }

  void _setHost(String? hostId) {
    final preservedBranch = _sourceBranch;
    _update(() {
      _selectedHostId = hostId;
      _sourceBranch = null;
    });
    _hostEnrollment.clearError();
    final project = _project;
    if (!_useProjectCheckout && project != null) {
      unawaited(_loadBranches(project, preserveBranch: preservedBranch));
    }
  }

  /// The host list follows the Remote Hosts controller, so a host removed
  /// while the form is open drops the selection back to This Device or the
  /// project's primary host.
  void _fallBackWhenHostRemoved(List<RemoteHostView> previousHosts) {
    final remoteId = normalizedRemoteHostId(_selectedHostId);
    if (remoteId == null ||
        remoteHostViewById(previousHosts, remoteId) == null ||
        remoteHostViewById(widget.hosts, remoteId) != null) {
      return;
    }
    final fallback = initialWorkspaceHostId(project: _project, requested: null);
    if (fallback == _selectedHostId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedHostId != fallback) {
        _setHost(fallback);
      }
    });
  }

  Widget _hostPicker({required bool enabled}) {
    final notice = _hostEnrollmentNotice();
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        WorkspaceHostPicker(
          hostId: _selectedHostId,
          hosts: widget.hosts,
          remoteOnlyProject: _project?.isRemoteOnly ?? false,
          supportsRemoteSshWorkspaces: widget.supportsRemoteSshWorkspaces,
          enabled: enabled,
          onChanged: _setHost,
          onAddHost: widget.onAddHost,
          onOpenHost: widget.onOpenHost,
          onOpenRemoteHosts: widget.onOpenRemoteHosts,
        ),
        if (notice != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          notice,
        ],
      ],
    );
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
      hostLabel: remoteHostViewLabel(widget.hosts, _selectedHostId),
      controller: _hostEnrollment,
      enabled: !_working && _created == null,
      onAdd: _addProjectToSelectedHost,
    );
  }
}
