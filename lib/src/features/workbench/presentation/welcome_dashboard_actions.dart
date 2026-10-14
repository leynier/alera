part of 'welcome_dashboard.dart';

const String _localHostMenuValue = 'local';
const String _noParentMenuValue = '';

extension _WelcomeDashboardActions on _WelcomeDashboardState {
  void _onHostEnrollmentChanged() {
    if (!mounted) {
      return;
    }
    _update(() {});
    final project = _boundProject;
    if (project != null &&
        _branchesAwaitEnrollment &&
        !_useProjectCheckout &&
        _enrollmentFor(project) == .enrolled) {
      unawaited(_loadBranches(_hosts.resolve(project)));
    }
  }

  ProjectHostEnrollmentController get _hosts => _hostEnrollment!;

  ProjectHostEnrollment _enrollmentFor(Project project) {
    return projectHostEnrollment(
      project: _hosts.resolve(project),
      hostId: _selectedHostId,
      supportsProjectHosts: _hosts.supported,
    );
  }

  void _syncBoundProject(Project? project) {
    final id = project?.id;
    if (_hasBoundProject && _boundProjectId == id) {
      _boundProject = project;
      return;
    }
    _hasBoundProject = true;
    _boundProjectId = id;
    _boundProject = project;
    final saved = id == null ? null : _savedSelection.projects[id];
    _selectedHostId = initialWorkspaceHostId(
      project: project,
      requested: saved?.hostId,
    );
    _selectedParentId = saved?.parentWorkspaceId;
    _useProjectCheckout =
        (saved?.useProjectCheckout ?? true) ||
        !(project?.isGitRepository ?? false);
    _sourceBranch = null;
    _branches = const <String>[];
    _loadingBranches = false;
    _branchesAwaitEnrollment = false;
    _error = null;
    _branchGeneration++;
    if (project != null && !_useProjectCheckout) {
      // Binding runs during build; load the restored worktree's branches after.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _boundProjectId == project.id && !_useProjectCheckout) {
          unawaited(_loadBranches(project));
        }
      });
    }
  }

  /// Saves the draft once typing pauses, so each keystroke does not rewrite
  /// the view prefs.
  void _onPromptChanged() {
    if (_promptController.text == _savedPrompt) {
      _promptSave?.cancel();
      return;
    }
    _promptSave?.cancel();
    _promptSave = Timer(const Duration(milliseconds: 500), _savePrompt);
  }

  void _savePrompt() {
    final prompt = _promptController.text;
    if (prompt == _savedPrompt) {
      return;
    }
    _savedPrompt = prompt;
    _workbench.setHomeComposerPrompt(prompt);
  }

  /// Records the current choices so the next Home visit, or the next launch,
  /// starts from them.
  void _saveSelection() {
    final saved = _savedSelection;
    final projectId = _boundProjectId;
    ref
        .read(workbenchControllerProvider.notifier)
        .setHomeComposerPrefs(
          saved.copyWith(
            projectId: _explicitProjectId ?? saved.projectId,
            profileId: _explicitProfileId ?? saved.profileId,
            projects: projectId == null
                ? saved.projects
                : <String, HomeComposerProjectPrefs>{
                    ...saved.projects,
                    projectId: HomeComposerProjectPrefs(
                      hostId: normalizedRemoteHostId(_selectedHostId),
                      parentWorkspaceId: _selectedParentId,
                      useProjectCheckout: _useProjectCheckout,
                      sourceBranch:
                          _sourceBranch ??
                          saved.projects[projectId]?.sourceBranch,
                    ),
                  },
          ),
        );
  }

  String? _savedSourceBranch(String projectId, List<String> branches) {
    final branch = _savedSelection.projects[projectId]?.sourceBranch;
    return branch != null && branches.contains(branch) ? branch : null;
  }

  String? _hostSelectionError(AsyncValue<List<SshTarget>> targets) {
    if (!targets.hasValue) {
      return null;
    }
    return remoteHostSelectionError(
      hostId: _selectedHostId,
      hosts: ref.read(remoteHostsControllerProvider).hosts,
      supportsRemoteSshWorkspaces: true,
    );
  }

  bool _fieldsReady({required Project project}) {
    if (_hosts.adding || _enrollmentFor(project) != .enrolled) {
      return false;
    }
    final checkout = _useProjectCheckout || !project.isGitRepository;
    if (!checkout && (_loadingBranches || (_sourceBranch ?? '').isEmpty)) {
      return false;
    }
    final targets = ref.read(sshTargetsProvider);
    if (isRemoteWorkspaceHostId(_selectedHostId) && !targets.hasValue) {
      return false;
    }
    return _hostSelectionError(targets) == null;
  }

  List<Workspace> _parentWorkspaces(WorkbenchState state) {
    final projectNameById = <String, String>{
      for (final project in state.projects) project.id: project.name,
    };
    final workspaces = <Workspace>[
      for (final project in state.projects)
        for (final workspace in state.workspacesFor(project.id))
          if (workspace.isActive) workspace,
    ];
    workspaces.sort(
      (left, right) => compareWorkspaceParentSelectionKeys(
        (
          isDefault: left.isMain,
          projectId: left.projectId,
          projectName: projectNameById[left.projectId] ?? left.projectId,
          workspaceId: left.id,
          workspaceName: left.name,
        ),
        (
          isDefault: right.isMain,
          projectId: right.projectId,
          projectName: projectNameById[right.projectId] ?? right.projectId,
          workspaceId: right.id,
          workspaceName: right.name,
        ),
        preferredProjectId: _boundProjectId,
      ),
    );
    return workspaces;
  }

  Future<void> _loadBranches(Project project) async {
    if (!mounted) {
      return;
    }
    final hostId = _selectedHostId;
    final generation = ++_branchGeneration;
    if (_enrollmentFor(project) != .enrolled) {
      _branchesAwaitEnrollment = true;
      _update(() {
        _loadingBranches = false;
        _branches = const <String>[];
        _sourceBranch = null;
      });
      return;
    }
    _branchesAwaitEnrollment = false;
    _update(() {
      _loadingBranches = true;
      _error = null;
      _branches = const <String>[];
      _sourceBranch = null;
    });
    try {
      if (!mounted) {
        return;
      }
      final branches = isRemoteWorkspaceHostId(hostId)
          ? (await ref
                    .read(workbenchControllerProvider.notifier)
                    .loadHostBranchCatalog(project, hostId))
                .branches
          : await ref
                .read(workbenchControllerProvider.notifier)
                .listSourceBranches(project);
      if (!_catalogStillCurrent(generation, hostId, project.id)) {
        return;
      }
      final preferred = await _preferredSource(project);
      if (!_catalogStillCurrent(generation, hostId, project.id)) {
        return;
      }
      _update(() {
        if (generation != _branchGeneration) {
          return;
        }
        _branches = branches;
        _loadingBranches = false;
        if (_useProjectCheckout) {
          return;
        }
        _sourceBranch = pickDefaultSourceBranch(
          branches,
          preferred: _savedSourceBranch(project.id, branches) ?? preferred,
        );
      });
    } catch (error) {
      if (!_catalogStillCurrent(generation, hostId, project.id)) {
        return;
      }
      _update(() {
        _loadingBranches = false;
        _sourceBranch = null;
        _error = userFacingExceptionMessage(error);
      });
    }
  }

  /// Clears a stale loading flag when no newer catalog request owns it.
  bool _catalogStillCurrent(int generation, String? hostId, String projectId) {
    if (!mounted || generation != _branchGeneration) {
      return false;
    }
    if (_selectedHostId == hostId && _boundProjectId == projectId) {
      return true;
    }
    _update(() {
      if (generation == _branchGeneration) {
        _loadingBranches = false;
      }
    });
    return false;
  }

  Future<String?> _preferredSource(Project project) async {
    if (!mounted) {
      return null;
    }
    try {
      final effective = await ref
          .read(projectConfigServiceProvider)
          .resolve(project);
      if (!mounted) {
        return null;
      }
      return effective.config.newWorkspace.preferredSourceBranch;
    } catch (_) {
      return null;
    }
  }

  void _addProjectToSelectedHost() {
    final project = _boundProject;
    final hostId = normalizedRemoteHostId(_selectedHostId);
    if (project != null && hostId != null) {
      unawaited(_hosts.add(project, hostId));
    }
  }

  Future<void> _pickProject(
    BuildContext context,
    List<Project> projects,
  ) async {
    final selected = await showHomeComposerMenu(
      context: context,
      choices: <HomeComposerMenuChoice>[
        for (final project in projects)
          HomeComposerMenuChoice(
            value: project.id,
            label: project.name,
            selected: project.id == _boundProjectId,
          ),
      ],
    );
    if (selected == null) {
      return;
    }
    _update(() {
      _explicitProjectId = selected;
      _error = null;
    });
    _saveSelection();
  }

  Future<void> _pickProfile(
    BuildContext context,
    List<AgentProfile> profiles,
  ) async {
    final selected = await showHomeComposerMenu(
      context: context,
      choices: <HomeComposerMenuChoice>[
        for (final profile in profiles)
          HomeComposerMenuChoice(
            value: profile.id,
            label: profile.name,
            selected:
                profile.id ==
                _profileFor(
                  profiles,
                  ref
                      .read(settingsControllerProvider)
                      .agents
                      .defaultAgentProfileId,
                )?.id,
            leading: AgentIdentityIcon(
              agentType: AgentType.tryParse(profile.agentType) ?? .codex,
              size: AleraTokens.iconLg,
              showTooltip: false,
            ),
          ),
      ],
    );
    if (selected != null) {
      _update(() => _explicitProfileId = selected);
      _saveSelection();
    }
  }

  Future<void> _pickHost(
    BuildContext context,
    List<RemoteHostView> hosts,
  ) async {
    final current = normalizedRemoteHostId(_selectedHostId);
    final selected = await showHomeComposerMenu(
      context: context,
      choices: <HomeComposerMenuChoice>[
        HomeComposerMenuChoice(
          value: _localHostMenuValue,
          label: 'This Device',
          selected: current == null,
          leading: const Icon(
            AleraIcons.workspaceMain,
            size: AleraTokens.iconMd,
          ),
        ),
        for (final host in hosts)
          HomeComposerMenuChoice(
            value: host.id,
            label: host.pickerLabel,
            selected: host.id == current,
            leading: AleraHostOsIcon(os: host.os, size: AleraTokens.iconMd),
            enabled: host.status.isReady,
          ),
      ],
    );
    if (selected == null || !mounted) {
      return;
    }
    final project = _boundProject;
    final reload =
        project != null && !_useProjectCheckout && project.isGitRepository;
    _update(() {
      _selectedHostId = selected == _localHostMenuValue ? null : selected;
      _sourceBranch = null;
      _branches = const <String>[];
      _error = null;
      // Checkout mode does not start a replacement catalog. Drop the one in
      // flight so a late result cannot stick the menu or restore its error.
      _branchGeneration++;
      if (!reload) {
        _loadingBranches = false;
      }
    });
    if (!mounted) {
      return;
    }
    _hosts.clearError();
    _saveSelection();
    if (reload) {
      unawaited(_loadBranches(project));
    }
  }

  Future<void> _pickParent(
    BuildContext context,
    List<Workspace> parents,
    WorkbenchState state,
  ) async {
    final names = <String, String>{
      for (final project in state.projects) project.id: project.name,
    };
    final selected = await showHomeComposerMenu(
      context: context,
      choices: <HomeComposerMenuChoice>[
        HomeComposerMenuChoice(
          value: _noParentMenuValue,
          label: 'No Parent',
          selected: _selectedParentId == null,
        ),
        for (final workspace in parents)
          HomeComposerMenuChoice(
            value: workspace.id,
            label: _homeParentLabel(workspace, names),
            selected: workspace.id == _selectedParentId,
          ),
      ],
    );
    if (selected == null) {
      return;
    }
    _update(() => _selectedParentId = selected.isEmpty ? null : selected);
    _saveSelection();
  }

  Future<void> _submit() async {
    final workbench = ref.read(workbenchControllerProvider);
    final projects = sortProjectsForSelection(<Project>[
      for (final project in workbench.projects) _hosts.resolve(project),
    ]);
    final project = _projectFor(projects, workbench.activeProjectId);
    final profiles =
        ref.read(agentProfilesProvider).asData?.value ?? const <AgentProfile>[];
    final profile = _profileFor(
      profiles,
      ref.read(settingsControllerProvider).agents.defaultAgentProfileId,
    );
    final prompt = _promptController.text.trim();
    final checkout = project == null
        ? _useProjectCheckout
        : _useProjectCheckout || !project.isGitRepository;
    if (project == null ||
        profile == null ||
        prompt.isEmpty ||
        (!checkout && (_sourceBranch ?? '').isEmpty)) {
      _update(
        () =>
            _error = 'Complete the prompt, project, branch, and agent profile.',
      );
      return;
    }
    if (!_fieldsReady(project: project)) {
      return;
    }
    final parents = _parentWorkspaces(workbench);
    final parentId = _selectedParentId;
    final parentStillExists =
        parentId != null &&
        parents.any((workspace) => workspace.id == parentId);
    final done = ref
        .read(backgroundSetupJobsProvider.notifier)
        .enqueuePromptWorkspace(
          PromptWorkspaceCreateRequest(
            useProjectCheckout: checkout,
            project: project,
            prompt: prompt,
            profileId: profile.id,
            sourceBranch: checkout ? '' : _sourceBranch!,
            parentWorkspaceId: parentStillExists ? parentId : null,
            hostId: normalizedRemoteHostId(_selectedHostId),
            autoAssignSection:
                workbench.supportsSections && workbench.sections.isNotEmpty,
          ),
        );
    if (done == null) {
      _update(
        () => _error = 'A workspace is already being created from this prompt.',
      );
      return;
    }
    done.ignore();
    _promptController.clear();
    _promptSave?.cancel();
    _savePrompt();
    _update(() => _error = null);
  }
}
