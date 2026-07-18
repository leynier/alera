import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/rename_host_dialog.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/application/host_dashboard_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/presentation/terminal_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HostDashboardScreen extends ConsumerWidget {
  const HostDashboardScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(hostDashboardDataProvider(host.id));
    final connection = ref.watch(hostConnectionControllerProvider(host.id));
    // Resolve the freshest profile so a rename reflects while this screen is
    // open; the constructor argument is the fallback before the list loads.
    final currentHost =
        ref
            .watch(pairedHostsControllerProvider)
            .value
            ?.where((profile) => profile.id == host.id)
            .firstOrNull ??
        host;
    return Scaffold(
      appBar: AppBar(
        title: Text(currentHost.effectiveName),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                showRenameHostDialog(context, ref, currentHost);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'rename',
                child: Text('Rename Host'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: switch (data) {
          AsyncData(value: final dashboard) => ListView(
            padding: AleraTokens.pagePadding,
            children: <Widget>[
              _StatusCard(host: host, status: dashboard.status),
              const SizedBox(height: AleraTokens.spaceMd),
              _ProjectsCard(
                projects: dashboard.projects,
                branchesByProject: dashboard.branchesByProject,
              ),
              const SizedBox(height: AleraTokens.spaceMd),
              _WorkspacesCard(workspaces: dashboard.workspaces),
              const SizedBox(height: AleraTokens.spaceMd),
              Text('Terminal', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AleraTokens.spaceSm),
              switch (connection) {
                AsyncData(value: final client) => TerminalPreview(
                  client: client,
                  workspaces: dashboard.workspaces,
                ),
                _ => const _MutedPanel(text: 'Connection Closed'),
              },
            ],
          ),
          AsyncError(:final error) => _ErrorState(
            error: error,
            onRetry: () {
              ref.invalidate(hostConnectionControllerProvider(host.id));
            },
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.host, required this.status});

  final PairedHostProfile host;
  final MobileRuntimeStatus status;

  @override
  Widget build(BuildContext context) {
    final activeDevices = status.devices
        .where((device) => device.revokedAt == null)
        .length
        .toString();
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.router_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Text('Host', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            _KeyValue(label: 'Connection', value: 'Online'),
            _KeyValue(label: 'Endpoint', value: host.endpoint),
            _KeyValue(label: 'Runtime ID', value: host.runtimeId),
            _KeyValue(label: 'Device ID', value: host.deviceId),
            _KeyValue(label: 'Paired Devices', value: activeDevices),
          ],
        ),
      ),
    );
  }
}

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({
    required this.projects,
    required this.branchesByProject,
  });

  final List<ProjectSummary> projects;
  final Map<String, ProjectBranches> branchesByProject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.account_tree_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Text(
                  'Projects',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            _KeyValue(label: 'Total', value: projects.length.toString()),
            if (projects.isEmpty)
              const _MutedText('No Projects')
            else
              for (final project in projects.take(AleraTokens.previewRowLimit))
                _ProjectRow(
                  project: project,
                  branches: branchesByProject[project.id],
                ),
          ],
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.branches});

  final ProjectSummary project;
  final ProjectBranches? branches;

  @override
  Widget build(BuildContext context) {
    final branchCount = branches?.branches.length;
    final subtitle = branchCount == null
        ? project.repoPath
        : '$branchCount Branches';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.folder_outlined),
      title: Text(project.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
    );
  }
}

class _WorkspacesCard extends StatelessWidget {
  const _WorkspacesCard({required this.workspaces});

  final List<WorkspaceSummary> workspaces;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.workspaces_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Text(
                  'Workspaces',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            _KeyValue(label: 'Total', value: workspaces.length.toString()),
            if (workspaces.isEmpty)
              const _MutedText('No Workspaces')
            else
              for (final workspace in workspaces.take(
                AleraTokens.previewRowLimit,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.terminal),
                  title: Text(workspace.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    workspace.branch ?? workspace.path,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'Connection Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MutedPanel extends StatelessWidget {
  const _MutedPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AleraTokens.border),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: _MutedText(text),
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: AleraTokens.keyColumnWidth,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
