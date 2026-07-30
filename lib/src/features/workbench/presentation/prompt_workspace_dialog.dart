import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_selection_order.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_parent_selection_order.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

part 'prompt_workspace_dialog_form.dart';

enum NewWorkspaceMode { fromPrompt, manual }

class PromptWorkspaceDialogResult {
  const PromptWorkspaceDialogResult({
    this.creation,
    this.agentTabId,
    this.openManual = false,
  });

  final WorkspaceCreationResult? creation;
  final String? agentTabId;
  final bool openManual;
}

class PromptWorkspaceDialog extends StatefulWidget {
  const PromptWorkspaceDialog({
    super.key,
    required this.projects,
    required this.agentProfiles,
    required this.loadBranches,
    required this.checkBranchExists,
    required this.workspaceBranches,
    required this.parentWorkspaces,
    required this.generateIdentity,
    required this.cancelGeneration,
    required this.createWorkspace,
    required this.launchAgent,
    this.initialProject,
  });

  final List<Project> projects;
  final List<AgentProfile> agentProfiles;
  final Project? initialProject;
  final Future<List<String>> Function(Project project) loadBranches;
  final Future<bool> Function(Project project, String branchName)
  checkBranchExists;
  final Set<String> Function(Project project) workspaceBranches;
  final List<Workspace> parentWorkspaces;
  final Future<GeneratedWorkspaceIdentity> Function({
    required String operationId,
    required String projectId,
    required String prompt,
  })
  generateIdentity;
  final Future<void> Function(String operationId) cancelGeneration;
  final Future<WorkspaceCreationResult> Function({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required String name,
    String? parentWorkspaceId,
  })
  createWorkspace;
  final Future<AgentProfileLaunchResult> Function({
    required String workspaceId,
    required String profileId,
    required String prompt,
  })
  launchAgent;

  @override
  State<PromptWorkspaceDialog> createState() => _PromptWorkspaceDialogState();
}

class _PromptWorkspaceDialogState extends State<PromptWorkspaceDialog> {
  final TextEditingController _promptController = TextEditingController();
  NewWorkspaceMode _mode = NewWorkspaceMode.fromPrompt;
  Project? _project;
  AgentProfile? _profile;
  List<String> _branches = const <String>[];
  String? _sourceBranch;
  String? _selectedParentWorkspaceId;
  bool _loadingBranches = false;
  bool _working = false;
  String? _phase;
  String? _error;
  WorkspaceCreationResult? _created;
  String? _activeOperationId;

  List<Project> get _orderedProjects =>
      sortProjectsForSelection(widget.projects);

  @override
  void initState() {
    super.initState();
    _project = _initialProject();
    _selectedParentWorkspaceId = _defaultParentWorkspaceId(_project);
    _profile = widget.agentProfiles.firstOrNull;
    final project = _project;
    if (project != null) {
      unawaited(_loadBranches(project));
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _update(VoidCallback update) => setState(update);

  Project? _initialProject() {
    final preferred = widget.initialProject;
    if (preferred != null) {
      for (final project in _orderedProjects) {
        if (project.id == preferred.id) {
          return project;
        }
      }
    }
    return _orderedProjects.firstOrNull;
  }

  Future<void> _loadBranches(Project project) async {
    setState(() {
      _loadingBranches = true;
      _error = null;
      _branches = const <String>[];
      _sourceBranch = null;
    });
    try {
      final branches = await widget.loadBranches(project);
      if (!mounted || _project?.id != project.id) {
        return;
      }
      setState(() {
        _branches = branches;
        _sourceBranch = _defaultBranch(branches);
        _loadingBranches = false;
      });
    } catch (error) {
      if (mounted && _project?.id == project.id) {
        setState(() {
          _loadingBranches = false;
          _error = error.toString();
        });
      }
    }
  }

  String? _defaultBranch(List<String> branches) {
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
    return branches.firstOrNull;
  }

  List<Workspace> get _parentWorkspaces {
    final projectNameById = <String, String>{
      for (final project in widget.projects) project.id: project.name,
    };
    final workspaces = <Workspace>[
      for (final workspace in widget.parentWorkspaces)
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
        preferredProjectId: _project?.id,
      ),
    );
    return workspaces;
  }

  String? _defaultParentWorkspaceId(Project? project) {
    if (project == null) {
      return null;
    }
    Workspace? firstProjectWorkspace;
    for (final workspace in _parentWorkspaces) {
      if (workspace.projectId != project.id) {
        continue;
      }
      firstProjectWorkspace ??= workspace;
      if (workspace.isMain) {
        return workspace.id;
      }
    }
    return firstProjectWorkspace?.id;
  }

  String _parentWorkspaceLabel(Workspace workspace) {
    Project? project;
    for (final candidate in _orderedProjects) {
      if (candidate.id == workspace.projectId) {
        project = candidate;
        break;
      }
    }
    final branch = workspace.branch?.trim();
    final suffix = branch == null || branch.isEmpty ? '' : ' - $branch';
    return '${project?.name ?? workspace.projectId} / ${workspace.name}$suffix';
  }

  void _selectProject(Project project) {
    _update(() {
      _project = project;
      _selectedParentWorkspaceId = _defaultParentWorkspaceId(project);
    });
    unawaited(_loadBranches(project));
  }

  Future<void> _submit() async {
    final project = _project;
    final profile = _profile;
    final sourceBranch = _sourceBranch;
    final prompt = _promptController.text.trim();
    if (project == null ||
        profile == null ||
        sourceBranch == null ||
        prompt.isEmpty) {
      setState(
        () =>
            _error = 'Complete The Prompt, Project, Branch, And Agent Profile.',
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _phase = 'Generating Workspace Identity';
    });
    try {
      WorkspaceCreationResult? creation;
      Object? collisionError;
      for (var attempt = 0; attempt < 2; attempt++) {
        final identityPrompt = attempt == 0
            ? prompt
            : '$prompt\n\nThe previous generated workspace identity was unavailable. Generate a different workspace name and branch.';
        final operationId = const Uuid().v4();
        _activeOperationId = operationId;
        final GeneratedWorkspaceIdentity identity;
        try {
          identity = await widget.generateIdentity(
            operationId: operationId,
            projectId: project.id,
            prompt: identityPrompt,
          );
        } finally {
          if (_activeOperationId == operationId) {
            _activeOperationId = null;
          }
        }
        if (!mounted) {
          return;
        }
        setState(() => _phase = 'Checking Generated Branch');
        final collision =
            widget.workspaceBranches(project).contains(identity.branchName) ||
            await widget.checkBranchExists(project, identity.branchName);
        if (collision) {
          collisionError = StateError(
            'The Generated Branch "${identity.branchName}" Already Exists.',
          );
          continue;
        }
        setState(() => _phase = 'Creating Workspace');
        try {
          creation = await widget.createWorkspace(
            project: project,
            sourceBranch: sourceBranch,
            newBranchName: identity.branchName,
            name: identity.workspaceName,
            parentWorkspaceId: _selectedParentWorkspaceId,
          );
          break;
        } catch (error) {
          if (attempt == 0 && _looksLikeCollision(error)) {
            collisionError = error;
            continue;
          }
          rethrow;
        }
      }
      if (creation == null) {
        throw collisionError ??
            StateError(
              'AI Text Could Not Generate An Available Workspace Identity.',
            );
      }
      _created = creation;
      if (!mounted) {
        return;
      }
      setState(() => _phase = 'Starting Agent');
      final launch = await widget.launchAgent(
        workspaceId: creation.workspace.id,
        profileId: profile.id,
        prompt: prompt,
      );
      if (mounted) {
        Navigator.of(context).pop(
          PromptWorkspaceDialogResult(
            creation: creation,
            agentTabId: launch.tabId,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _phase = null;
          _error = error.toString();
        });
      }
    }
  }

  bool _looksLikeCollision(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('already exists') ||
        message.contains('workspace for branch');
  }

  Future<void> _cancelGeneration() async {
    final operationId = _activeOperationId;
    if (operationId != null) {
      await widget.cancelGeneration(operationId);
    }
  }

  Future<void> _retryAgent() async {
    final creation = _created;
    final profile = _profile;
    final prompt = _promptController.text.trim();
    if (creation == null || profile == null || prompt.isEmpty) {
      return;
    }
    setState(() {
      _working = true;
      _phase = 'Starting Agent';
      _error = null;
    });
    try {
      final launch = await widget.launchAgent(
        workspaceId: creation.workspace.id,
        profileId: profile.id,
        prompt: prompt,
      );
      if (mounted) {
        Navigator.of(context).pop(
          PromptWorkspaceDialogResult(
            creation: creation,
            agentTabId: launch.tabId,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _phase = null;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 620,
      maxHeight: 720,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(AleraIcons.gitFork, color: AleraTokens.accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'New Workspace',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _working
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(AleraIcons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraSegmentedButton<NewWorkspaceMode>(
              dense: true,
              segments: const <ButtonSegment<NewWorkspaceMode>>[
                ButtonSegment<NewWorkspaceMode>(
                  value: NewWorkspaceMode.fromPrompt,
                  label: Text('From Prompt'),
                  icon: Icon(AleraIcons.agent, size: 16),
                ),
                ButtonSegment<NewWorkspaceMode>(
                  value: NewWorkspaceMode.manual,
                  label: Text('Manual'),
                  icon: Icon(AleraIcons.gitBranch, size: 16),
                ),
              ],
              selected: _mode,
              onSelectionChanged: _working
                  ? (_) {}
                  : (mode) => setState(() => _mode = mode),
            ),
            const SizedBox(height: AleraTokens.space20),
            if (_mode == NewWorkspaceMode.manual)
              _buildManualMode(theme)
            else
              _buildPromptMode(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildManualMode(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose Every Workspace Setting Yourself, Including The Branch Name And Optional Parent Workspace.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(const PromptWorkspaceDialogResult(openManual: true)),
            child: const Text('Continue Manually'),
          ),
        ),
      ],
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
