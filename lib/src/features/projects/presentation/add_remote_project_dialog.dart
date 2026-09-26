import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_host_os.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

part 'add_remote_project_dialog_fields.dart';

typedef RegisterRemoteProject = Future<Project> Function(
  RemoteProjectRequest request,
);

/// The SSH hosts a project can be created on: only a bootstrapped host runs
/// the runtime that inspects or clones the folder.
List<SshTarget> remoteProjectHosts(Iterable<SshTarget> sshTargets) {
  return <SshTarget>[
    for (final target in sshTargets)
      if (target.bootstrapStatus == SshBootstrapStatus.installed) target,
  ];
}

/// Creates a project that lives only on an SSH host, from a folder that is
/// already there or by cloning a repository into the host's projects folder.
/// Pops with the created [Project]; the project list refreshes on its own from
/// the runtime's `projectsChanged`.
class const AddRemoteProjectDialog({
  super.key,
  required final List<SshTarget> sshTargets,
  required final RegisterRemoteProject registerRemoteProject,
}) extends StatefulWidget {
  @override
  State<AddRemoteProjectDialog> createState() => _AddRemoteProjectDialogState();
}

class _AddRemoteProjectDialogState extends State<AddRemoteProjectDialog> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _cloneUrlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String? _hostId;
  RemoteProjectSource _source = .existingFolder;
  ProjectKind _kind = .gitRepository;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hosts = remoteProjectHosts(widget.sshTargets);
    if (hosts.length == 1) {
      _hostId = hosts.single.id;
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    _cloneUrlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// A host that stopped being bootstrapped while the form was open is no
  /// longer a choice.
  String? get _selectedHostId {
    final hostId = _hostId;
    return remoteProjectHosts(widget.sshTargets)
            .any((target) => target.id == hostId)
        ? hostId
        : null;
  }

  RemoteProjectRequest? get _request => remoteProjectRequestFrom(
    hostId: _selectedHostId,
    source: _source,
    path: _pathController.text,
    cloneUrl: _cloneUrlController.text,
    name: _nameController.text,
    kind: _kind,
  );

  void _edited() => setState(() => _error = null);

  Future<void> _submit() async {
    final request = _request;
    if (request == null || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final project = await widget.registerRemoteProject(request);
      if (mounted) {
        Navigator.of(context).pop(project);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = userFacingExceptionMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosts = remoteProjectHosts(widget.sshTargets);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Add Remote Project',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: SingleChildScrollView(
                child: _RemoteProjectFields(
                  hosts: hosts,
                  hostId: _selectedHostId,
                  source: _source,
                  kind: _kind,
                  enabled: !_submitting,
                  pathController: _pathController,
                  cloneUrlController: _cloneUrlController,
                  nameController: _nameController,
                  onHostChanged: (value) => setState(() {
                    _hostId = value;
                    _error = null;
                  }),
                  onSourceChanged: (value) => setState(() {
                    _source = value;
                    _error = null;
                  }),
                  onKindChanged: (value) => setState(() {
                    _kind = value;
                    _error = null;
                  }),
                  onEdited: _edited,
                  onSubmitted: () => unawaited(_submit()),
                ),
              ),
            ),
            if (_submitting) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              const _RemoteProjectProgress(),
            ],
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              AleraInlineNotice(message: error, tone: .error),
            ],
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _submitting || _request == null
                      ? null
                      : () => unawaited(_submit()),
                  child: const Text('Add Project'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
