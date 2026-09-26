import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_new_run_form.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_saved_proposals.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowNewRunPage extends ConsumerStatefulWidget {
  const WorkflowNewRunPage({
    super.key,
    required this.onCreated,
    required this.onBack,
  });
  final ValueChanged<String> onCreated;
  final VoidCallback onBack;
  @override
  ConsumerState<WorkflowNewRunPage> createState() => _WorkflowNewRunPageState();
}

class _WorkflowNewRunPageState extends ConsumerState<WorkflowNewRunPage> {
  bool _saved = false;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(workflowLifecycleRepositoryProvider);
    final workbench = ref.watch(workbenchControllerProvider);
    final profiles = ref.watch(agentProfilesProvider);
    final projects = {
      for (final project in workbench.projects)
        if (project.kind == ProjectKind.gitRepository) project.id: project,
    };
    return IndexedStack(
      index: _saved ? 1 : 0,
      children: [
        Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _saved = true),
                child: const Text('Saved Proposals'),
              ),
            ),
            if (profiles.hasError)
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Text(
                  'Agent Profiles could not be loaded: ${profiles.error}',
                ),
              ),
            Expanded(
              child: WorkflowNewRunForm(
                repository: repository,
                catalog: ref.watch(workflowCatalogRepositoryProvider),
                workspaces: [
                  for (final workspace
                      in workbench.workspacesByProject.values.expand(
                        (items) => items,
                      ))
                    if (projects.containsKey(workspace.projectId) &&
                        workspace.isActive &&
                        workspace.hostId == 'local' &&
                        !workspace.workflowOwned)
                      (
                        id: workspace.id,
                        label:
                            '${projects[workspace.projectId]!.name} / ${workspace.name}',
                      ),
                ],
                profiles: profiles.value ?? const [],
                onCreated: widget.onCreated,
                onBack: widget.onBack,
              ),
            ),
          ],
        ),
        if (_saved)
          WorkflowSavedProposals(
            repository: repository,
            onSelect: widget.onCreated,
            onNew: () => setState(() => _saved = false),
          ),
      ],
    );
  }
}
