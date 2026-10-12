import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:alera/src/features/projects/presentation/add_remote_project_dialog.dart';
import 'package:alera/src/features/projects/presentation/project_host_add_form.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:alera/src/features/projects/presentation/remote_project_fields.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_status_badge.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

enum AddProjectToHostMode { existingProject, newRemoteProject }

/// The Git projects that can also go on [hostId], sorted by name. A folder
/// project stays on the one host it was created on.
List<Project> projectsAddableToHost(Iterable<Project> projects, String hostId) {
  return <Project>[
    for (final project in projects)
      if (project.isGitRepository && !project.isOnHost(hostId)) project,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Puts a project on one host: an existing Git project, cloned there or
/// registered from a path the host already has, or a new project that lives
/// only on that host. Pops with the project as the runtime now reports it.
/// With nothing to add, it opens on New Remote Project.
class const AddProjectToHostDialog({
  super.key,
  required final String hostId,
  required final List<RemoteHostView> hosts,
  required final List<Project> projects,
  required final AddProjectToHost addProjectToHost,
  required final RegisterRemoteProject registerRemoteProject,
  final AddProjectToHostMode initialMode = .existingProject,
}) extends StatefulWidget {
  @override
  State<AddProjectToHostDialog> createState() => _AddProjectToHostDialogState();
}

class _AddProjectToHostDialogState extends State<AddProjectToHostDialog> {
  late final ProjectHostEnrollmentController _enrollment =
      ProjectHostEnrollmentController(widget.addProjectToHost);
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _cloneUrlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  late AddProjectToHostMode _mode;
  String? _projectId;
  RemoteProjectSource _source = .existingFolder;
  ProjectKind _kind = .gitRepository;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = _addable.isEmpty ? .newRemoteProject : widget.initialMode;
  }

  @override
  void dispose() {
    _enrollment.dispose();
    _pathController.dispose();
    _cloneUrlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  RemoteHostView? get _host {
    for (final host in widget.hosts) {
      if (host.id == widget.hostId) {
        return host;
      }
    }
    return null;
  }

  List<Project> get _addable =>
      projectsAddableToHost(widget.projects, widget.hostId);

  bool get _busy => _submitting || _enrollment.adding;

  RemoteProjectRequest? get _request => remoteProjectRequestFrom(
    hostId: widget.hostId,
    source: _source,
    path: _pathController.text,
    cloneUrl: _cloneUrlController.text,
    name: _nameController.text,
    kind: _kind,
  );

  Future<void> _addExisting(Project project) async {
    final refreshed = await _enrollment.add(project, widget.hostId);
    if (refreshed != null && mounted) {
      Navigator.of(context).pop(refreshed);
    }
  }

  Future<void> _submitRemote() async {
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
    final host = _host;
    return ListenableBuilder(
      listenable: _enrollment,
      builder: (context, _) => AleraDialog(
        maxWidth: AleraTokens.dialogWideWidth,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              AleraDialogHeader(
                title: 'Add Project to ${host?.alias ?? widget.hostId}',
                onClose: () => Navigator.of(context).pop(),
                trailing: host == null
                    ? null
                    : RemoteHostStatusBadge(status: host.status),
              ),
              const SizedBox(height: AleraTokens.space12),
              Flexible(child: SingleChildScrollView(child: _buildBody(host))),
              const SizedBox(height: AleraTokens.space16),
              _buildFooter(host),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(RemoteHostView? host) {
    if (host == null) {
      return const AleraInlineNotice(
        message: 'This host is no longer registered.',
        tone: .error,
      );
    }
    if (!host.status.isReady) {
      return AleraInlineNotice(
        message:
            'Projects can be added once ${host.alias} is ready. Open the host in Settings to finish its setup.',
        tone: .warning,
      );
    }
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        // The control has no disabled state; a request in flight ignores it.
        IgnorePointer(
          ignoring: _busy,
          child: AleraSegmentedButton<AddProjectToHostMode>(
            selected: _mode,
            onSelectionChanged: (mode) => setState(() {
              _mode = mode;
              _error = null;
              _enrollment.clearError();
            }),
            segments: const <ButtonSegment<AddProjectToHostMode>>[
              ButtonSegment<AddProjectToHostMode>(
                value: .existingProject,
                icon: Icon(AleraIcons.gitBranch, size: AleraTokens.iconLg),
                label: Text('Existing Project'),
              ),
              ButtonSegment<AddProjectToHostMode>(
                value: .newRemoteProject,
                icon: Icon(AleraIcons.newFolder, size: AleraTokens.iconLg),
                label: Text('New Remote Project'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        switch (_mode) {
          .existingProject => _buildExisting(host),
          .newRemoteProject => _buildNewRemote(host),
        },
      ],
    );
  }

  Widget _buildExisting(RemoteHostView host) {
    final addable = _addable;
    if (addable.isEmpty) {
      return AleraInlineNotice(
        message:
            'Every Git project is already on ${host.alias}. Create a new remote project instead.',
      );
    }
    final selected = addable.where((p) => p.id == _projectId).firstOrNull;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraDropdownField<String>(
          value: selected?.id,
          labelText: 'Project',
          hintText: 'Select Project',
          enabled: !_enrollment.adding,
          filterable: addable.length > 6,
          filterHintText: 'Search Projects',
          entries: <AleraDropdownFieldEntry<String>>[
            for (final project in addable)
              AleraDropdownFieldEntry<String>(
                value: project.id,
                label: project.name,
                leading: const Icon(
                  AleraIcons.gitBranch,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
          ],
          onChanged: (projectId) {
            _enrollment.clearError();
            setState(() => _projectId = projectId);
          },
        ),
        const SizedBox(height: AleraTokens.space12),
        ProjectHostAddForm(
          controller: _enrollment,
          onAdd: selected == null
              ? null
              : () => unawaited(_addExisting(selected)),
        ),
      ],
    );
  }

  Widget _buildNewRemote(RemoteHostView host) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        RemoteProjectFields(
          hosts: <RemoteHostView>[host],
          hostId: host.id,
          source: _source,
          kind: _kind,
          enabled: !_submitting,
          pathController: _pathController,
          cloneUrlController: _cloneUrlController,
          nameController: _nameController,
          onHostChanged: null,
          onSourceChanged: (value) => setState(() {
            _source = value;
            _error = null;
          }),
          onKindChanged: (value) => setState(() {
            _kind = value;
            _error = null;
          }),
          onEdited: () => setState(() => _error = null),
          onSubmitted: () => unawaited(_submitRemote()),
        ),
        if (_submitting) ...<Widget>[
          const SizedBox(height: AleraTokens.space16),
          const RemoteProjectProgress(),
        ],
        if (_error case final error?) ...<Widget>[
          const SizedBox(height: AleraTokens.space16),
          AleraInlineNotice(message: error, tone: .error),
        ],
      ],
    );
  }

  Widget _buildFooter(RemoteHostView? host) {
    final showSubmit =
        host != null &&
        host.status.isReady &&
        _mode == AddProjectToHostMode.newRemoteProject;
    return Row(
      mainAxisAlignment: .end,
      children: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (showSubmit) ...<Widget>[
          const SizedBox(width: AleraTokens.space8),
          FilledButton(
            onPressed: _submitting || _request == null
                ? null
                : () => unawaited(_submitRemote()),
            child: const Text('Add Project'),
          ),
        ],
      ],
    );
  }
}
