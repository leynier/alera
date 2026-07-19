import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String? _projectId;
  List<String> _branches = const <String>[];
  String? _sourceBranch;
  String? _parentWorkspaceId;
  bool _reuseExistingBranch = false;
  bool _loadingBranches = false;
  bool _creating = false;
  String? _error;
  WorkspaceCreationResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.projects.length == 1) {
      _selectProject(widget.projects.single.id);
    }
  }

  @override
  void dispose() {
    _branch.dispose();
    _name.dispose();
    super.dispose();
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
        setState(() {
          _result = result;
        });
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

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('New Workspace')),
      body: SafeArea(
        child: result != null
            ? _SetupReportView(
                result: result,
                onDone: () => Navigator.of(context).pop(true),
              )
            : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _projectId,
          decoration: const InputDecoration(labelText: 'Project'),
          items: <DropdownMenuItem<String>>[
            for (final project in widget.projects)
              DropdownMenuItem<String>(
                value: project.id,
                child: Text(project.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _creating
              ? null
              : (value) {
                  if (value != null) {
                    _selectProject(value);
                  }
                },
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        TextField(
          controller: _branch,
          enabled: !_creating,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Branch Name',
            helperText: 'The Worktree Branch For This Workspace',
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _reuseExistingBranch,
          onChanged: _creating
              ? null
              : (value) {
                  setState(() {
                    _reuseExistingBranch = value;
                  });
                },
          title: const Text('Reuse Existing Branch'),
        ),
        if (!_reuseExistingBranch) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          if (_loadingBranches)
            const Center(child: CircularProgressIndicator())
          else
            DropdownButtonFormField<String>(
              initialValue: _sourceBranch,
              decoration: const InputDecoration(labelText: 'Source Branch'),
              items: <DropdownMenuItem<String>>[
                for (final branch in _branches)
                  DropdownMenuItem<String>(
                    value: branch,
                    child: Text(branch, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _creating
                  ? null
                  : (value) {
                      setState(() {
                        _sourceBranch = value;
                      });
                    },
            ),
        ],
        const SizedBox(height: AleraTokens.spaceLg),
        TextField(
          controller: _name,
          enabled: !_creating,
          decoration: const InputDecoration(
            labelText: 'Display Name (Optional)',
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        DropdownButtonFormField<String?>(
          initialValue: _parentWorkspaceId,
          decoration: const InputDecoration(labelText: 'Parent Workspace'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No Parent'),
            ),
            for (final workspace in widget.workspaces)
              if (workspace.projectId == _projectId)
                DropdownMenuItem<String?>(
                  value: workspace.id,
                  child: Text(workspace.name, overflow: TextOverflow.ellipsis),
                ),
          ],
          onChanged: _creating
              ? null
              : (value) {
                  setState(() {
                    _parentWorkspaceId = value;
                  });
                },
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AleraTokens.spaceXl),
        FilledButton.icon(
          onPressed: _canSubmit ? _create : null,
          icon: _creating
              ? const SizedBox.square(
                  dimension: AleraTokens.spaceLg,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                  ),
                )
              : const Icon(Icons.add),
          label: Text(_creating ? 'Creating' : 'Create Workspace'),
        ),
      ],
    );
  }
}

class _SetupReportView extends StatelessWidget {
  const _SetupReportView({required this.result, required this.onDone});

  final WorkspaceCreationResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline, color: AleraTokens.success),
            const SizedBox(width: AleraTokens.spaceSm),
            Expanded(
              child: Text(
                result.workspace.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        for (final step in result.steps)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              step.succeeded ? Icons.check : Icons.close,
              color: step.succeeded ? AleraTokens.success : AleraTokens.error,
            ),
            title: Text(step.label, overflow: TextOverflow.ellipsis),
            subtitle: step.message == null
                ? null
                : Text(step.message!, overflow: TextOverflow.ellipsis),
          ),
        const SizedBox(height: AleraTokens.spaceXl),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
