import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../network/mobile_runtime_client.dart';
import '../storage/host_repository.dart';
import '../theme/alera_tokens.dart';
import '../widgets/terminal_preview.dart';

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({
    super.key,
    required this.host,
    required this.hostRepository,
  });

  final PairedHostProfile host;
  final HostRepository hostRepository;

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  late Future<_DashboardData> _dataFuture;
  MobileRuntimeClient? _client;

  @override
  void initState() {
    super.initState();
    _dataFuture = _connectAndLoad();
  }

  @override
  void dispose() {
    final client = _client;
    _client = null;
    if (client != null) {
      unawaited(client.dispose());
    }
    super.dispose();
  }

  void _retry() {
    final client = _client;
    _client = null;
    if (client != null) {
      unawaited(client.dispose());
    }
    setState(() {
      _dataFuture = _connectAndLoad();
    });
  }

  Future<_DashboardData> _connectAndLoad() async {
    final deviceToken = await widget.hostRepository.readDeviceToken(
      widget.host.id,
    );
    if (deviceToken == null || deviceToken.trim().isEmpty) {
      throw StateError('Device Token Is Missing.');
    }
    final client = await MobileRuntimeClient.connect(widget.host.endpoint);
    var retainedByState = false;
    try {
      await client.authenticate(
        deviceId: widget.host.deviceId,
        deviceToken: deviceToken,
      );
      final status = await client.mobileStatus();
      final projects = await client.listProjects();
      final workspaces = await client.listWorkspaces();
      final branchesByProject = <String, ProjectBranches>{};
      for (final project in projects.take(AleraTokens.previewRowLimit)) {
        try {
          branchesByProject[project.id] = await client.listBranches(project.id);
        } on Object {
          // Branch discovery can fail for invalid or moved repos; keep the
          // dashboard usable and surface the project/workspace state.
        }
      }
      if (!mounted) {
        throw StateError('Connection Closed.');
      }
      _client = client;
      retainedByState = true;
      return _DashboardData(
        status: status,
        projects: projects,
        workspaces: workspaces,
        branchesByProject: branchesByProject,
      );
    } on Object {
      if (!retainedByState) {
        await client.dispose();
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.host.displayName)),
      body: SafeArea(
        child: FutureBuilder<_DashboardData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final error = snapshot.error;
            if (error != null) {
              return _ErrorState(error: error, onRetry: _retry);
            }
            final data = snapshot.requireData;
            final client = _client;
            return ListView(
              padding: AleraTokens.pagePadding,
              children: <Widget>[
                _StatusCard(host: widget.host, status: data.status),
                const SizedBox(height: AleraTokens.spaceMd),
                _ProjectsCard(
                  projects: data.projects,
                  branchesByProject: data.branchesByProject,
                ),
                const SizedBox(height: AleraTokens.spaceMd),
                _WorkspacesCard(workspaces: data.workspaces),
                const SizedBox(height: AleraTokens.spaceMd),
                Text(
                  'Terminal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                if (client == null)
                  const _MutedPanel(text: 'Connection Closed')
                else
                  TerminalPreview(client: client, workspaces: data.workspaces),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.status,
    required this.projects,
    required this.workspaces,
    required this.branchesByProject,
  });

  final MobileRuntimeStatus status;
  final List<ProjectSummary> projects;
  final List<WorkspaceSummary> workspaces;
  final Map<String, ProjectBranches> branchesByProject;
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
