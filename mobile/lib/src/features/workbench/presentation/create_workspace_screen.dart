import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
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

class CreateWorkspaceScreen extends ConsumerStatefulWidget {
  const CreateWorkspaceScreen({
    super.key,
    required this.hostId,
    required this.projects,
    required this.workspaces,
  });

  final String hostId;
  final List<ProjectSummary> projects;
  final List<WorkspaceSummary> workspaces;

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
  bool _reuseExistingBranch = false;
  bool _createAnother = false;
  bool _loadingBranches = false;
  bool _creating = false;
  String? _error;

  List<ProjectSummary> get _orderedProjects =>
      sortProjectsForSelection(widget.projects);

  List<WorkspaceSummary> get _orderedParentWorkspaces {
    final projectNameById = <String, String>{
      for (final project in widget.projects) project.id: project.name,
    };
    return <WorkspaceSummary>[...widget.workspaces]..sort(
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
        preferredProjectId: _projectId,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (_orderedProjects.length == 1) {
      _selectProject(_orderedProjects.single.id);
    }
    final initialPromptProject = _orderedProjects.firstOrNull;
    if (initialPromptProject != null) {
      Future<void>.microtask(
        () => ref
            .read(promptWorkspaceControllerProvider(widget.hostId).notifier)
            .selectProject(initialPromptProject.id),
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
        : 'Workspace Created';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
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
                segments: const <ButtonSegment<bool>>[
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
                ],
                selected: <bool>{_fromPrompt},
                onSelectionChanged: (selection) {
                  setState(() => _fromPrompt = selection.first);
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

  Widget _buildPromptForm(BuildContext context) {
    final promptState = ref.watch(
      promptWorkspaceControllerProvider(widget.hostId),
    );
    final controller = ref.read(
      promptWorkspaceControllerProvider(widget.hostId).notifier,
    );
    final created = promptState.creation;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        TextField(
          controller: _prompt,
          enabled: !promptState.loading && created == null,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Initial Prompt',
            hintText: 'Describe What The Agent Should Build',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        DropdownButtonFormField<String>(
          initialValue: promptState.projectId,
          decoration: const InputDecoration(labelText: 'Project'),
          items: <DropdownMenuItem<String>>[
            for (final project in _orderedProjects)
              DropdownMenuItem<String>(
                value: project.id,
                child: Text(project.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: promptState.loading || created != null
              ? null
              : (value) {
                  if (value != null) {
                    controller.selectProject(value);
                  }
                },
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        DropdownButtonFormField<String>(
          key: ValueKey<String?>(
            'prompt-source-${promptState.projectId}-${promptState.sourceBranch}',
          ),
          initialValue: promptState.sourceBranch,
          decoration: const InputDecoration(labelText: 'Source Branch'),
          items: <DropdownMenuItem<String>>[
            for (final branch in promptState.branches)
              DropdownMenuItem<String>(
                value: branch,
                child: Text(branch, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: promptState.loading || created != null
              ? null
              : (value) {
                  if (value != null) {
                    controller.selectSourceBranch(value);
                  }
                },
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        DropdownButtonFormField<String>(
          key: ValueKey<String?>('prompt-profile-${promptState.profileId}'),
          initialValue: promptState.profileId,
          decoration: InputDecoration(
            labelText: 'Agent Profile',
            helperText: promptState.profiles.isEmpty
                ? 'Create An Agent Profile In Desktop Settings'
                : null,
          ),
          items: <DropdownMenuItem<String>>[
            for (final profile in promptState.profiles)
              DropdownMenuItem<String>(
                value: profile.id,
                child: Text(profile.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: promptState.loading || created != null
              ? null
              : (value) {
                  if (value != null) {
                    controller.selectProfile(value);
                  }
                },
        ),
        if (promptState.error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            promptState.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _createAnother,
          onChanged: promptState.loading || created != null
              ? null
              : (value) {
                  setState(() => _createAnother = value ?? false);
                },
          title: const Text('Create Another'),
          subtitle: const Text('Keep This Screen Open After Creation'),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        if (promptState.loading)
          Row(
            children: <Widget>[
              const SizedBox.square(
                dimension: AleraTokens.spaceLg,
                child: CircularProgressIndicator(
                  strokeWidth: AleraTokens.strokeSm,
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              Expanded(child: Text(promptState.phase ?? 'Working')),
              if (promptState.phase == 'Generating Workspace Identity')
                TextButton(
                  onPressed: controller.cancelGeneration,
                  child: const Text('Cancel'),
                ),
            ],
          )
        else if (created != null)
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openWorkspace(created),
                  child: const Text('Open Workspace'),
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              Expanded(
                child: FilledButton(
                  onPressed: () => _retryPromptAgent(controller),
                  child: const Text('Retry Agent'),
                ),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed:
                promptState.projectId == null ||
                    promptState.sourceBranch == null ||
                    promptState.profileId == null
                ? null
                : () => _createFromPrompt(controller),
            icon: const Icon(Icons.smart_toy_outlined),
            label: const Text('Create And Start Agent'),
          ),
      ],
    );
  }

  Future<void> _createFromPrompt(PromptWorkspaceController controller) async {
    final workspaceBranches = <String>{
      for (final workspace in widget.workspaces)
        if (workspace.branch != null) workspace.branch!,
    };
    await controller.create(
      prompt: _prompt.text,
      workspaceBranches: workspaceBranches,
    );
    if (!mounted) {
      return;
    }
    final state = ref.read(promptWorkspaceControllerProvider(widget.hostId));
    final creation = state.creation;
    final tabId = state.agentTabId;
    if (creation != null && tabId != null) {
      if (_createAnother) {
        _showCreationMessage(creation);
        _prompt.clear();
        controller.resetForAnother();
      } else {
        _openWorkspace(creation, tabId: tabId);
      }
    }
  }

  Future<void> _retryPromptAgent(PromptWorkspaceController controller) async {
    await controller.retryAgent(_prompt.text);
    if (!mounted) {
      return;
    }
    final state = ref.read(promptWorkspaceControllerProvider(widget.hostId));
    final creation = state.creation;
    final tabId = state.agentTabId;
    if (creation != null && tabId != null) {
      if (_createAnother) {
        _showCreationMessage(creation);
        _prompt.clear();
        controller.resetForAnother();
      } else {
        _openWorkspace(creation, tabId: tabId);
      }
    }
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
