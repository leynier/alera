import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_selection_order.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_parent_selection_order.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'create_workspace_manual.dart';
part 'create_workspace_prompt.dart';

class CreateWorkspaceScreen extends ConsumerStatefulWidget {
  const CreateWorkspaceScreen({
    super.key,
    required this.hostId,
    required this.projects,
    required this.workspaces,
    this.defaultAgentProfileId,
    this.supportsPromptWorkspaceCreation = true,
  });

  final String hostId;
  final List<ProjectSummary> projects;
  final List<WorkspaceSummary> workspaces;
  final String? defaultAgentProfileId;
  final bool supportsPromptWorkspaceCreation;

  @override
  ConsumerState<CreateWorkspaceScreen> createState() =>
      _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends ConsumerState<CreateWorkspaceScreen> {
  final TextEditingController _branch = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _prompt = TextEditingController();
  bool _fromPrompt = true;
  String? _projectId;
  List<String> _branches = const <String>[];
  String? _sourceBranch;
  String? _parentWorkspaceId;
  String? _promptParentWorkspaceId;
  bool _reuseExistingBranch = false;
  bool _createAnother = false;
  bool _loadingBranches = false;
  bool _creating = false;
  String? _error;

  List<ProjectSummary> get _orderedProjects => sortProjectsForSelection(
    widget.projects.where((project) => project.supportsLinkedWorkspaces),
  );

  List<WorkspaceSummary> get _orderedParentWorkspaces =>
      _parentWorkspacesFor(_projectId);

  List<WorkspaceSummary> _parentWorkspacesFor(String? preferredProjectId) {
    final projectNameById = <String, String>{
      for (final project in widget.projects) project.id: project.name,
    };
    return <WorkspaceSummary>[...widget.workspaces]
        .where((workspace) => workspace.status == 'active')
        .toList(growable: false)
      ..sort(
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
          preferredProjectId: preferredProjectId,
        ),
      );
  }

  String? _defaultParentWorkspaceId(String? projectId) {
    if (projectId == null) {
      return null;
    }
    final candidates = _parentWorkspacesFor(projectId);
    for (final workspace in candidates) {
      if (workspace.projectId == projectId && workspace.isMain) {
        return workspace.id;
      }
    }
    for (final workspace in candidates) {
      if (workspace.projectId == projectId) {
        return workspace.id;
      }
    }
    return null;
  }

  String _parentWorkspaceLabel(WorkspaceSummary workspace) {
    String? projectName;
    for (final project in widget.projects) {
      if (project.id == workspace.projectId) {
        projectName = project.name;
        break;
      }
    }
    final branch = workspace.branch?.trim();
    final suffix = branch == null || branch.isEmpty ? '' : ' - $branch';
    return '${projectName ?? workspace.projectId} / ${workspace.name}$suffix';
  }

  @override
  void initState() {
    super.initState();
    _fromPrompt = widget.supportsPromptWorkspaceCreation;
    if (_orderedProjects.length == 1) {
      _selectProject(_orderedProjects.single.id);
    }
    final initialPromptProject = _orderedProjects.firstOrNull;
    if (widget.supportsPromptWorkspaceCreation &&
        initialPromptProject != null) {
      _promptParentWorkspaceId = _defaultParentWorkspaceId(
        initialPromptProject.id,
      );
      Future<void>.microtask(
        () => ref
            .read(promptWorkspaceControllerProvider(widget.hostId).notifier)
            .selectProject(
              initialPromptProject.id,
              defaultAgentProfileId: widget.defaultAgentProfileId,
            ),
      );
    }
  }

  @override
  void dispose() {
    _branch.dispose();
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _update(VoidCallback update) => setState(update);

  void _selectPromptProject(
    String projectId,
    PromptWorkspaceController controller,
  ) {
    setState(() {
      _promptParentWorkspaceId = _defaultParentWorkspaceId(projectId);
    });
    controller.selectProject(
      projectId,
      defaultAgentProfileId: widget.defaultAgentProfileId,
    );
  }

  Future<void> _selectProject(String projectId) async {
    setState(() {
      _projectId = projectId;
      _branches = const <String>[];
      _sourceBranch = null;
      _parentWorkspaceId = null;
      _loadingBranches = true;
    });
    try {
      final client = await ref.read(
        workspaceClientProvider(widget.hostId).future,
      );
      final branches = await client.listBranches(projectId);
      if (!mounted || _projectId != projectId) {
        return;
      }
      setState(() {
        _branches = branches.branches;
        _sourceBranch = branches.branches.isEmpty
            ? null
            : branches.branches.first;
      });
    } on Object catch (error) {
      if (mounted && _projectId == projectId) {
        setState(() {
          _error = 'Could Not Load Branches: $error';
        });
      }
    } finally {
      if (mounted && _projectId == projectId) {
        setState(() {
          _loadingBranches = false;
        });
      }
    }
  }

  bool get _canSubmit {
    if (_creating || _projectId == null || _branch.text.trim().isEmpty) {
      return false;
    }
    return _reuseExistingBranch || _sourceBranch != null;
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      final result = await ref
          .read(workspaceListControllerProvider(widget.hostId).notifier)
          .createWorkspace(
            projectId: _projectId!,
            branch: _branch.text.trim(),
            sourceBranch: _reuseExistingBranch ? null : _sourceBranch,
            reuseExistingBranch: _reuseExistingBranch,
            name: name.isEmpty ? null : name,
            parentWorkspaceId: _parentWorkspaceId,
          );
      if (mounted) {
        _showCreationMessage(result);
        if (_createAnother) {
          await _resetManualForm();
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _resetManualForm() async {
    final projectId = _projectId;
    _branch.clear();
    _name.clear();
    setState(() {
      _parentWorkspaceId = null;
      _reuseExistingBranch = false;
      _error = null;
    });
    if (projectId != null) {
      await _selectProject(projectId);
    }
  }

  void _showCreationMessage(WorkspaceCreationResult creation) {
    final message = creation.setupLaunchError != null
        ? 'Workspace Created, But Setup Could Not Start'
        : creation.hasSetupWarnings
        ? 'Workspace Created With Setup Warnings'
        : creation.parentLinkError != null
        ? 'Workspace Created, But Parent Link Failed'
        : 'Workspace Created';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final promptState = widget.supportsPromptWorkspaceCreation
        ? ref.watch(promptWorkspaceControllerProvider(widget.hostId))
        : const PromptWorkspaceState();
    final modeLocked = _creating || promptState.loading;
    final segments = widget.supportsPromptWorkspaceCreation
        ? const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: true,
              label: Text('From Prompt'),
              icon: Icon(Icons.smart_toy_outlined),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text('Manual'),
              icon: Icon(Icons.account_tree_outlined),
            ),
          ]
        : const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              label: Text('Manual'),
              icon: Icon(Icons.account_tree_outlined),
            ),
          ];
    return Scaffold(
      appBar: AppBar(title: const Text('New Workspace')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.spaceLg,
                AleraTokens.spaceMd,
                AleraTokens.spaceLg,
                0,
              ),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: segments,
                selected: <bool>{_fromPrompt},
                onSelectionChanged: modeLocked
                    ? null
                    : (selection) {
                        if (selection.isNotEmpty) {
                          setState(() => _fromPrompt = selection.first);
                        }
                      },
              ),
            ),
            Expanded(
              child: _fromPrompt
                  ? _buildPromptForm(context)
                  : _buildForm(context),
            ),
          ],
        ),
      ),
    );
  }

  void _openWorkspace(WorkspaceCreationResult creation, {String? tabId}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceTabsScreen(
          hostId: widget.hostId,
          workspace: creation.workspace,
          initialTabId: tabId,
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
