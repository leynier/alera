import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/projects/presentation/project_host_add_form.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:alera/src/features/projects/presentation/project_host_row.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_selection.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// The hosts a Git project is on, with the way to add it to another ready
/// host and to forget it on one. Removing never deletes files. [onOpenHost]
/// and [onManageHosts] open Settings > Remote Hosts; [onAddHost] runs Add
/// Host.
class const ProjectHostsDialog({
  super.key,
  required final Project project,
  required final List<RemoteHostView> hosts,
  required final Future<List<ProjectHost>> Function() loadHosts,
  required final AddProjectToHost addProjectToHost,
  required final Future<List<ProjectHost>> Function(String hostId)
  removeFromHost,
  final ValueChanged<String>? onOpenHost,
  final VoidCallback? onManageHosts,
  final VoidCallback? onAddHost,
}) extends StatefulWidget {
  @override
  State<ProjectHostsDialog> createState() => _ProjectHostsDialogState();
}

class _ProjectHostsDialogState extends State<ProjectHostsDialog> {
  late final ProjectHostEnrollmentController _enrollment =
      ProjectHostEnrollmentController(widget.addProjectToHost);
  List<ProjectHost>? _hosts;
  String? _loadError;
  String? _removeError;
  String? _removingHostId;
  String? _addHostId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _enrollment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final hosts = await widget.loadHosts();
      if (mounted) {
        setState(() => _hosts = hosts);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = userFacingExceptionMessage(error));
      }
    }
  }

  List<RemoteHostView> get _addableHosts {
    final hosts = _hosts ?? const <ProjectHost>[];
    return <RemoteHostView>[
      for (final remoteHost in widget.hosts)
        if (remoteHost.status.isReady &&
            !hosts.any((host) => host.hostId == remoteHost.id))
          remoteHost,
    ];
  }

  Future<void> _add(String hostId) async {
    final refreshed = await _enrollment.add(widget.project, hostId);
    if (!mounted || refreshed == null) {
      return;
    }
    setState(() => _addHostId = null);
    await _load();
  }

  Future<void> _remove(ProjectHost host, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Remove From Host?',
        message:
            '${widget.project.name} will no longer be on $label. Files on the host are not deleted.',
        confirmLabel: 'Remove',
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _removingHostId = host.hostId;
      _removeError = null;
    });
    try {
      final hosts = await widget.removeFromHost(host.hostId);
      if (mounted) {
        setState(() => _hosts = hosts);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _removeError = userFacingExceptionMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _removingHostId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: '${widget.project.name} Hosts',
              onClose: () => Navigator.of(context).pop(),
              trailing: widget.onManageHosts == null
                  ? null
                  : TextButton(
                      onPressed: widget.onManageHosts,
                      child: const Text('Manage Remote Hosts'),
                    ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(child: SingleChildScrollView(child: _buildBody())),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final hosts = _hosts;
    final loadError = _loadError;
    if (hosts == null && loadError != null) {
      return Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: <Widget>[
          _ErrorText(loadError),
          const SizedBox(height: AleraTokens.space12),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    if (hosts == null) {
      return const Padding(
        padding: EdgeInsets.all(AleraTokens.space24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final onOpenHost = widget.onOpenHost;
    final removeError = _removeError ?? loadError;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraPanel(
          children: <Widget>[
            for (final host in hosts)
              ProjectHostRow(
                host: host,
                remoteHost: remoteHostViewById(widget.hosts, host.hostId),
                onOpenHost: onOpenHost == null
                    ? null
                    : () => onOpenHost(
                        normalizedRemoteHostId(host.hostId) ?? host.hostId,
                      ),
                removing: _removingHostId == host.hostId,
                removalBlockedReason: projectHostRemovalBlockedReason(
                  primary: host.primary,
                  workspaceCount: host.workspaceCount,
                  hostCount: hosts.length,
                ),
                onRemove: _removingHostId != null
                    ? null
                    : () => unawaited(
                        _remove(
                          host,
                          remoteHostViewLabel(widget.hosts, host.hostId),
                        ),
                      ),
              ),
          ],
        ),
        if (removeError != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          _ErrorText(removeError),
        ],
        const SizedBox(height: AleraTokens.space20),
        const AleraSectionHeader(
          label: 'Add to Another Host',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: AleraTokens.space8),
        _buildAddSection(),
      ],
    );
  }

  Widget _buildAddSection() {
    final addable = _addableHosts;
    if (addable.isEmpty) {
      final onAddHost = widget.onAddHost;
      final anyReady = widget.hosts.any((host) => host.status.isReady);
      return AleraInlineNotice(
        message: anyReady ? 'This project is already on every ready host.' : 'No remote host is ready. Install the Alera runtime on a host to add this project there.',
        child: onAddHost == null
            ? null
            : Align(
                alignment: .centerLeft,
                child: TextButton(
                  onPressed: onAddHost,
                  child: const Text('Add Host'),
                ),
              ),
      );
    }
    final addHostId = addable.any((host) => host.id == _addHostId)
        ? _addHostId
        : null;
    return ListenableBuilder(
      listenable: _enrollment,
      builder: (context, _) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraDropdownField<String>(
            value: addHostId,
            labelText: 'Host',
            hintText: 'Select Host',
            enabled: !_enrollment.adding,
            filterable: addable.length > 4,
            filterHintText: 'Search Hosts',
            entries: <AleraDropdownFieldEntry<String>>[
              for (final host in addable)
                AleraDropdownFieldEntry<String>(
                  value: host.id,
                  label: host.pickerLabel,
                  leading: AleraHostOsIcon(
                    os: host.os,
                    size: AleraTokens.iconMd,
                  ),
                ),
            ],
            onChanged: (hostId) {
              _enrollment.clearError();
              setState(() => _addHostId = hostId);
            },
          ),
          const SizedBox(height: AleraTokens.space12),
          ProjectHostAddForm(
            controller: _enrollment,
            onAdd: addHostId == null ? null : () => unawaited(_add(addHostId)),
          ),
        ],
      ),
    );
  }
}

class const _ErrorText(final String message) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.error),
    );
  }
}
