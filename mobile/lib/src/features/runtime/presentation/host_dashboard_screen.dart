import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/rename_host_dialog.dart';
import 'package:alera_mobile/src/features/projects/presentation/projects_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/application/host_dashboard_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const HostDashboardScreen({
  super.key,
  required final PairedHostProfile host,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(hostDashboardDataProvider(host.id));
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
        centerTitle: true,
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
                onOpen: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ProjectsScreen(host: currentHost),
                  ),
                ),
              ),
              const SizedBox(height: AleraTokens.spaceMd),
              _WorkspacesCard(workspaces: dashboard.workspaces),
              const SizedBox(height: AleraTokens.spaceMd),
              _AutomationsCard(
                onOpen: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AutomationsScreen(host: currentHost),
                  ),
                ),
              ),
            ],
          ),
          AsyncError(:final error) => _ErrorState(
            error: error,
            onRetry: () {
              unawaited(
                ref
                    .read(hostConnectionControllerProvider(host.id).notifier)
                    .reconnectNow()
                    .whenComplete(() {
                      ref.invalidate(hostDashboardDataProvider(host.id));
                    }),
              );
            },
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class const _StatusCard({
  required final PairedHostProfile host,
  required final MobileRuntimeStatus status,
}) extends StatelessWidget {
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
          crossAxisAlignment: .start,
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

class const _ProjectsCard({
  required final List<ProjectSummary> projects,
  required final Map<String, ProjectBranches> branchesByProject,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .start,
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
                const Spacer(),
                IconButton(
                  onPressed: onOpen,
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'Open Projects',
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            _KeyValue(label: 'Total', value: projects.length.toString()),
            if (projects.isEmpty)
              const _MutedText('No projects')
            else
              for (final project in projects.take(AleraTokens.previewRowLimit))
                _ProjectRow(
                  project: project,
                  branches: branchesByProject[project.id],
                  onTap: onOpen,
                ),
          ],
        ),
      ),
    );
  }
}

class const _ProjectRow({
  required final ProjectSummary project,
  required final ProjectBranches? branches,
  required final VoidCallback onTap,
}) extends StatelessWidget {
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
      title: Text(project.name, overflow: .ellipsis),
      subtitle: Text(subtitle, overflow: .ellipsis),
      onTap: onTap,
    );
  }
}

class const _WorkspacesCard({required final List<WorkspaceSummary> workspaces})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .start,
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
              const _MutedText('No workspaces')
            else
              for (final workspace in workspaces.take(
                AleraTokens.previewRowLimit,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.terminal),
                  title: Text(workspace.name, overflow: .ellipsis),
                  subtitle: Text(
                    workspace.branch ?? workspace.path,
                    overflow: .ellipsis,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class const _AutomationsCard({required final VoidCallback onOpen})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.checklist_rtl,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            const Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Text('Automations'),
                  SizedBox(height: AleraTokens.space2),
                  Text('View schedules and start approved runs.'),
                ],
              ),
            ),
            IconButton(
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Open Automations',
            ),
          ],
        ),
      ),
    );
  }
}

class const _ErrorState({
  required final Object error,
  required final VoidCallback onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'Connection failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: .center,
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

class const _MutedText(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class const _KeyValue({
  required final String label,
  required final String value,
}) extends StatelessWidget {
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
              overflow: .ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
