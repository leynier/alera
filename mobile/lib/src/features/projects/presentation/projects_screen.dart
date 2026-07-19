import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/projects/application/projects_controller.dart';
import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:alera_mobile/src/features/projects/presentation/project_creation_dialogs.dart';
import 'package:alera_mobile/src/features/projects/presentation/project_setup_screen.dart';
import 'package:alera_mobile/src/features/projects/presentation/remote_directory_picker_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ProjectAction { rename, setup, remove }

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectsControllerProvider(host.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: SafeArea(
        child: switch (state) {
          AsyncData(value: final snapshot) when !snapshot.supported =>
            const _UnsupportedState(),
          AsyncData(value: final snapshot) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(projectsControllerProvider(host.id));
              await ref.read(projectsControllerProvider(host.id).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                if (snapshot.cloneJobs.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AleraTokens.spaceLg,
                      AleraTokens.spaceLg,
                      AleraTokens.spaceLg,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: <Widget>[
                        for (final job in snapshot.cloneJobs.take(5))
                          _CloneJobCard(
                            job: job,
                            onCancel: job.isActive
                                ? () => ref
                                      .read(
                                        projectsControllerProvider(
                                          host.id,
                                        ).notifier,
                                      )
                                      .cancelClone(job.id)
                                : null,
                            onOpen: job.workspaceId == null
                                ? null
                                : () => _openWorkspace(
                                    context,
                                    ref,
                                    job.workspaceId!,
                                  ),
                          ),
                      ],
                    ),
                  ),
                if (snapshot.projects.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyProjects(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(
                      top: AleraTokens.spaceMd,
                      bottom: AleraTokens.spaceXxl * 3,
                    ),
                    sliver: SliverList.builder(
                      itemCount: snapshot.projects.length,
                      itemBuilder: (context, index) {
                        final project = snapshot.projects[index];
                        return _ProjectListTile(
                          project: project,
                          onAction: (action) => _handleProjectAction(
                            context,
                            ref,
                            project,
                            action,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          AsyncError(:final error) => _ErrorState(
            error: error,
            onRetry: () =>
                ref.invalidate(hostConnectionControllerProvider(host.id)),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
      floatingActionButton: state.value?.supported == true
          ? FloatingActionButton.extended(
              onPressed: () => _addProject(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Project'),
            )
          : null,
    );
  }

  Future<void> _addProject(BuildContext context, WidgetRef ref) async {
    final choice = await showAddProjectSheet(context);
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case AddProjectChoice.existingFolder:
        final path = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => RemoteDirectoryPickerScreen(
              hostId: host.id,
              actionLabel: 'Choose Project',
            ),
          ),
        );
        if (!context.mounted || path == null) return;
        final name = await showOptionalProjectNameDialog(context, path);
        if (!context.mounted || name == null) return;
        try {
          final result = await ref
              .read(projectsControllerProvider(host.id).notifier)
              .registerProject(path: path, name: name);
          if (context.mounted) {
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => WorkspaceTabsScreen(
                  hostId: host.id,
                  workspace: result.mainWorkspace,
                ),
              ),
            );
          }
        } on Object catch (error) {
          if (context.mounted) _showError(context, error);
        }
      case AddProjectChoice.cloneRepository:
        final draft = await showDialog<CloneProjectDraft>(
          context: context,
          builder: (_) => CloneProjectDialog(hostId: host.id),
        );
        if (!context.mounted || draft == null) return;
        try {
          await ref
              .read(projectsControllerProvider(host.id).notifier)
              .startClone(
                url: draft.url,
                parentPath: draft.parentPath,
                directoryName: draft.directoryName,
                name: draft.projectName,
              );
        } on Object catch (error) {
          if (context.mounted) _showError(context, error);
        }
    }
  }

  Future<void> _handleProjectAction(
    BuildContext context,
    WidgetRef ref,
    ProjectSummary project,
    _ProjectAction action,
  ) async {
    switch (action) {
      case _ProjectAction.rename:
        final name = await showDialog<String>(
          context: context,
          builder: (_) => AleraRenameDialog(
            title: 'Rename Project',
            labelText: 'Project Name',
            initialValue: project.name,
          ),
        );
        if (name == null) return;
        try {
          await ref
              .read(projectsControllerProvider(host.id).notifier)
              .renameProject(project.id, name);
        } on Object catch (error) {
          if (context.mounted) _showError(context, error);
        }
      case _ProjectAction.setup:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProjectSetupScreen(hostId: host.id, project: project),
          ),
        );
      case _ProjectAction.remove:
        try {
          final preview = await ref
              .read(projectsControllerProvider(host.id).notifier)
              .previewRemoval(project.id);
          if (!context.mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Remove Project'),
              content: Text(
                '${project.name}\n\n'
                '${preview.workspaceCount} Workspaces, '
                '${preview.tabCount} Tabs, '
                '${preview.activeSessionCount} Active Sessions.\n\n'
                'Files And Worktrees On The Host Will Not Be Deleted.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Remove Project'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await ref
                .read(projectsControllerProvider(host.id).notifier)
                .removeProject(project.id);
          }
        } on Object catch (error) {
          if (context.mounted) _showError(context, error);
        }
    }
  }

  Future<void> _openWorkspace(
    BuildContext context,
    WidgetRef ref,
    String workspaceId,
  ) async {
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(host.id).future,
      );
      final workspaces = await client.listWorkspaces();
      final workspace = workspaces
          .where((item) => item.id == workspaceId)
          .first;
      if (context.mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                WorkspaceTabsScreen(hostId: host.id, workspace: workspace),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({required this.project, required this.onAction});

  final ProjectSummary project;
  final ValueChanged<_ProjectAction> onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        project.kind == 'folder'
            ? Icons.folder_outlined
            : Icons.account_tree_outlined,
      ),
      title: Text(project.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        project.repoPath,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: AleraTokens.monoFontFamily),
      ),
      trailing: PopupMenuButton<_ProjectAction>(
        onSelected: onAction,
        itemBuilder: (_) => const <PopupMenuEntry<_ProjectAction>>[
          PopupMenuItem(value: _ProjectAction.rename, child: Text('Rename')),
          PopupMenuItem(
            value: _ProjectAction.setup,
            child: Text('Project Setup'),
          ),
          PopupMenuItem(
            value: _ProjectAction.remove,
            child: Text('Remove Project'),
          ),
        ],
      ),
    );
  }
}

class _CloneJobCard extends StatelessWidget {
  const _CloneJobCard({
    required this.job,
    required this.onCancel,
    required this.onOpen,
  });

  final ProjectCloneJob job;
  final VoidCallback? onCancel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = job.progressPercent;
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  job.status == ProjectCloneJobStatus.completed
                      ? Icons.check_circle_outline
                      : job.status == ProjectCloneJobStatus.failed
                      ? Icons.error_outline
                      : Icons.downloading_outlined,
                  color: job.status == ProjectCloneJobStatus.completed
                      ? AleraTokens.success
                      : job.status == ProjectCloneJobStatus.failed
                      ? AleraTokens.error
                      : AleraTokens.info,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Expanded(
                  child: Text(
                    job.message ?? 'Clone Job',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (progress != null) Text('$progress%'),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            if (job.isActive)
              LinearProgressIndicator(
                value: progress == null ? null : progress / 100,
              ),
            Text(
              job.destinationPath,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: AleraTokens.monoFontFamily,
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (job.error != null)
              Text(
                job.error!,
                style: const TextStyle(color: AleraTokens.error),
              ),
            if (onCancel != null || onOpen != null)
              Align(
                alignment: Alignment.centerRight,
                child: onCancel != null
                    ? TextButton(
                        onPressed: onCancel,
                        child: const Text('Cancel'),
                      )
                    : TextButton(
                        onPressed: onOpen,
                        child: const Text('Open Workspace'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedState extends StatelessWidget {
  const _UnsupportedState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: AleraTokens.contentPadding,
      child: Text(
        'Update The Alera Runtime To Manage Projects From Mobile.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.create_new_folder_outlined, size: AleraTokens.emptyIcon),
        SizedBox(height: AleraTokens.spaceLg),
        Text('No Projects'),
        SizedBox(height: AleraTokens.spaceSm),
        Text('Add A Folder Or Clone A Repository'),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: AleraTokens.spaceLg),
          FilledButton(onPressed: onRetry, child: const Text('Try Again')),
        ],
      ),
    ),
  );
}
