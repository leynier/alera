import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
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
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_host_os.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// The hosts a Git project is on, with the way to add it to another
/// bootstrapped host and to forget it on one. Removing never deletes files.
class const ProjectHostsDialog({
  super.key,
  required final Project project,
  required final List<SshTarget> sshTargets,
  required final Future<List<ProjectHost>> Function() loadHosts,
  required final AddProjectToHost addProjectToHost,
  required final Future<List<ProjectHost>> Function(String hostId)
  removeFromHost,
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

  List<SshTarget> get _addableTargets {
    final hosts = _hosts ?? const <ProjectHost>[];
    return <SshTarget>[
      for (final target in widget.sshTargets)
        if (target.bootstrapStatus == SshBootstrapStatus.installed &&
            !hosts.any((host) => host.hostId == target.id))
          target,
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
    final theme = Theme.of(context);
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
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(child: SingleChildScrollView(child: _buildBody(theme))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
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
    final targets = sshTargetsById(widget.sshTargets);
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
                target: targets[host.hostId],
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
                          workspaceHostLabel(widget.sshTargets, host.hostId),
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
        _buildAddSection(theme),
      ],
    );
  }

  Widget _buildAddSection(ThemeData theme) {
    final addable = _addableTargets;
    if (addable.isEmpty) {
      return Text(
        'This project is already on every bootstrapped host. Add SSH hosts in Settings → Remote Hosts.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      );
    }
    final addHostId = addable.any((target) => target.id == _addHostId)
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
              for (final target in addable)
                AleraDropdownFieldEntry<String>(
                  value: target.id,
                  label: sshTargetPickerLabel(target),
                  leading: AleraHostOsIcon(
                    os: sshTargetHostOs(target),
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
