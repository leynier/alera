import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:alera/src/features/projects/presentation/remote_project_fields.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

typedef RegisterRemoteProject = Future<Project> Function(
  RemoteProjectRequest request,
);

/// Creates a project that lives only on an SSH host, from a folder that is
/// already there or by cloning a repository into the host's projects folder.
/// Only a ready host runs the Alera runtime that inspects or clones the
/// folder; with none, the dialog offers [onAddHost] instead, once
/// [hostsLoading] is over. Pops with the
/// created [Project]; the project list refreshes on its own from the
/// runtime's `projectsChanged`.
class const AddRemoteProjectDialog({
  super.key,
  required final List<RemoteHostView> hosts,
  required final RegisterRemoteProject registerRemoteProject,
  final String? initialHostId,
  final VoidCallback? onAddHost,
  final bool hostsLoading = false,
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
    final ready = _readyHosts;
    if (ready.any((host) => host.id == widget.initialHostId)) {
      _hostId = widget.initialHostId;
    } else if (ready.length == 1) {
      _hostId = ready.single.id;
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    _cloneUrlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  List<RemoteHostView> get _readyHosts => <RemoteHostView>[
    for (final host in widget.hosts)
      if (host.status.isReady) host,
  ];

  /// A host that stopped being ready while the form was open is no longer a
  /// choice. One that became ready is picked when it is the only one.
  String? get _selectedHostId {
    final ready = _readyHosts;
    final hostId = _hostId;
    if (ready.any((host) => host.id == hostId)) {
      return hostId;
    }
    return ready.length == 1 && hostId == null ? ready.single.id : null;
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
    final noHostReady = _readyHosts.isEmpty;
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
                child: switch ((noHostReady, widget.hostsLoading)) {
                  (true, true) => const AleraEmptyState(
                    loading: true,
                    message: 'Loading hosts…',
                  ),
                  (true, false) => _NoHostReady(onAddHost: widget.onAddHost),
                  (false, _) => _buildFields(),
                },
              ),
            ),
            if (_submitting) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              const RemoteProjectProgress(),
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
                if (!noHostReady) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    onPressed: _submitting || _request == null
                        ? null
                        : () => unawaited(_submit()),
                    child: const Text('Add Project'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFields() {
    return RemoteProjectFields(
      hosts: widget.hosts,
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
    );
  }
}

class const _NoHostReady({required final VoidCallback? onAddHost})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final onAddHost = this.onAddHost;
    return AleraEmptyState(
      icon: AleraIcons.host,
      title: 'No host is ready',
      message:
          'Install the Alera runtime on a host before adding projects there.',
      action: onAddHost == null
          ? null
          : FilledButton(onPressed: onAddHost, child: const Text('Add Host')),
    );
  }
}
